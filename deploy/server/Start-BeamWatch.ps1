# AI195417 のタスクスケジューラ (Beam-watch) から呼ばれる起動ラッパー。
# 異常終了時は最大60秒の間隔で再起動し、ログが10MBを超えたら .1 へ移す。
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$appRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$otpBin = Join-Path $appRoot 'runtime\otp\bin'
$erl = Join-Path $otpBin 'erl.exe'
$shipment = Join-Path $appRoot 'shipment'
$logDir = Join-Path $appRoot 'logs'
$logFile = Join-Path $logDir 'beam_watch.log'
$outFile = Join-Path $logDir 'beam_watch.out.log'
$errFile = Join-Path $logDir 'beam_watch.err.log'

if (-not (Test-Path -LiteralPath $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

function Rotate-LogIfNeeded([string]$Path, [long]$MaxBytes = 10485760) {
    if (Test-Path -LiteralPath $Path) {
        $item = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
        if ($item -and $item.Length -ge $MaxBytes) {
            $backup = "$Path.1"
            if (Test-Path -LiteralPath $backup) {
                Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue
            }
            Move-Item -LiteralPath $Path -Destination $backup -Force -ErrorAction SilentlyContinue
        }
    }
}

function Write-WrapperLog([string]$Message) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -LiteralPath $logFile -Value "[$ts] [WRAPPER] $Message" -Encoding UTF8
}

$env:BEAM_WATCH_BIND = '0.0.0.0'
$env:BEAM_WATCH_PORT = '8010'
$env:PATH = "$otpBin;" + $env:PATH

$backoffSeconds = 5

while ($true) {
    Rotate-LogIfNeeded -Path $logFile
    Rotate-LogIfNeeded -Path $outFile
    Rotate-LogIfNeeded -Path $errFile

    if (-not (Test-Path -LiteralPath $erl -PathType Leaf)) {
        Write-WrapperLog "ERROR: erl.exe not found at $erl. Retrying in ${backoffSeconds}s..."
        Start-Sleep -Seconds $backoffSeconds
        $backoffSeconds = [Math]::Min($backoffSeconds * 2, 60)
        continue
    }

    $ebins = @(Get-ChildItem -Path (Join-Path $shipment '*\ebin') -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
    if ($ebins.Count -eq 0) {
        Write-WrapperLog "ERROR: shipment ebin was not found under $shipment. Retrying in ${backoffSeconds}s..."
        Start-Sleep -Seconds $backoffSeconds
        $backoffSeconds = [Math]::Min($backoffSeconds * 2, 60)
        continue
    }

    $started = Get-Date
    Write-WrapperLog "Starting BEAM Watch on $($env:BEAM_WATCH_BIND):$($env:BEAM_WATCH_PORT)"

    $arguments = @('-pa') + $ebins + @('-eval', 'beam_watch@@main:run(gui_server)', '-noshell')
    $proc = Start-Process -FilePath $erl `
        -ArgumentList $arguments `
        -WorkingDirectory $appRoot `
        -RedirectStandardOutput $outFile `
        -RedirectStandardError $errFile `
        -WindowStyle Hidden `
        -PassThru

    $proc.WaitForExit()
    $exitCode = $proc.ExitCode
    $elapsed = ((Get-Date) - $started).TotalSeconds
    Write-WrapperLog "Process exited with code $exitCode after $([Math]::Round($elapsed, 1))s."

    if ($elapsed -ge 60) {
        $backoffSeconds = 5
    } else {
        $backoffSeconds = [Math]::Min($backoffSeconds * 2, 60)
    }

    Write-WrapperLog "Restarting in ${backoffSeconds}s..."
    Start-Sleep -Seconds $backoffSeconds
}
