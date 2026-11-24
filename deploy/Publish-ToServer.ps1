# ローカルで erlang-shipment を作り終えたあと、AI195417 の C:\server\Apps\beam-watch へ配備する。
# OTP は未配置のときだけコピーする。監視対象の settings.json は未作成のときだけ置く。
[CmdletBinding()]
param(
    [string]$Server = 'AI195417',
    [string]$RemoteRoot = 'C:\server\Apps\beam-watch',
    [string]$OtpSource = 'C:\Program Files\Erlang OTP'
)

$ErrorActionPreference = 'Stop'
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$shipment = Join-Path $projectRoot 'build\erlang-shipment'
$uncRoot = "\\$Server\C`$\server\Apps\beam-watch"

if (-not (Test-Path -LiteralPath (Join-Path $shipment 'beam_watch\ebin\gui_server.beam'))) {
    throw "erlang-shipment was not found: $shipment"
}

New-Item -ItemType Directory -Force -Path @(
    "$uncRoot\runtime\otp",
    "$uncRoot\shipment",
    "$uncRoot\gui",
    "$uncRoot\deploy",
    "$uncRoot\logs",
    "$uncRoot\data"
) | Out-Null

$remoteErl = Join-Path $uncRoot 'runtime\otp\bin\erl.exe'
if (-not (Test-Path -LiteralPath $remoteErl)) {
    Write-Output "copying OTP to $RemoteRoot\runtime\otp"
    & robocopy $OtpSource "$uncRoot\runtime\otp" /E /XD doc /NFL /NDL /NP /R:2 /W:2
    if ($LASTEXITCODE -ge 8) {
        throw "robocopy OTP failed with exit $LASTEXITCODE"
    }
} else {
    Write-Output "OTP already present"
}

Write-Output "copying shipment"
& robocopy $shipment "$uncRoot\shipment" /MIR /NFL /NDL /NP /R:2 /W:2
if ($LASTEXITCODE -ge 8) {
    throw "robocopy shipment failed with exit $LASTEXITCODE"
}

Copy-Item -LiteralPath (Join-Path $projectRoot 'gui\index.html') -Destination "$uncRoot\gui\index.html" -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'gui\script.js') -Destination "$uncRoot\gui\script.js" -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'gui\style.css') -Destination "$uncRoot\gui\style.css" -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'server\Start-BeamWatch.ps1') -Destination "$uncRoot\deploy\Start-BeamWatch.ps1" -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'server\Register-BeamWatchTask.ps1') -Destination "$uncRoot\deploy\Register-BeamWatchTask.ps1" -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'server\BrowserCheck.ps1') -Destination "$uncRoot\deploy\BrowserCheck.ps1" -Force

$remoteSettings = "$uncRoot\gui\settings.json"
if (-not (Test-Path -LiteralPath $remoteSettings)) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'ai195417-settings.json') -Destination $remoteSettings -Force
    Write-Output "settings.json created"
} else {
    Write-Output "settings.json already exists and was left as-is"
}

Invoke-Command -ComputerName $Server -ScriptBlock {
    $register = 'C:\server\Apps\beam-watch\deploy\Register-BeamWatchTask.ps1'
    & 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -ExecutionPolicy Bypass -File $register
    if ($LASTEXITCODE -ne 0) {
        throw "Register-BeamWatchTask.ps1 exited with $LASTEXITCODE"
    }
}
Write-Output "publish finished"
