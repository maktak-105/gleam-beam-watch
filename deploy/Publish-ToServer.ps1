# ローカルで erlang-shipment を作り終えたあと、AI195417 の C:\server\Apps\beam-watch へ配備する。
# 手順: タスク停止 → バックアップ → 配置 → バッチログオン権の付与 → タスク登録 → 起動。
# OTP は未配置のときだけコピーする。監視対象の settings.json は未作成のときだけ置く。
# タスクの実行アカウントとパスワードは、実行時に AccountFile（bunai-server\サーバー.md）から読む。
# パスワードはリポジトリ・ログ・サーバーのファイルには書かない。
[CmdletBinding()]
param(
    [string]$Server = 'AI195417',
    [string]$RemoteRoot = 'C:\server\Apps\beam-watch',
    [string]$OtpSource = 'C:\Program Files\Erlang OTP',
    [string]$AccountFile = (Join-Path $PSScriptRoot '..\..\bunai-server\サーバー.md'),
    [string]$AccountDomain = 'GLOBAL'
)

$ErrorActionPreference = 'Stop'
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$shipment = Join-Path $projectRoot 'build\erlang-shipment'
$uncRoot = "\\$Server\C`$\server\Apps\beam-watch"
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

if (-not (Test-Path -LiteralPath (Join-Path $shipment 'beam_watch\ebin\gui_server.beam'))) {
    throw "erlang-shipment was not found: $shipment"
}

# 実行アカウント（ID: / PASS: の行）
if (-not (Test-Path -LiteralPath $AccountFile)) {
    throw "account file was not found: $AccountFile"
}
$accountLines = Get-Content -LiteralPath $AccountFile -Encoding UTF8
$accountId = ($accountLines | Where-Object { $_ -match '^\s*ID:' } | Select-Object -First 1)
$accountPass = ($accountLines | Where-Object { $_ -match '^\s*PASS:' } | Select-Object -First 1)
if (-not $accountId -or -not $accountPass) {
    throw "ID: / PASS: lines were not found in $AccountFile"
}
$taskUser = "$AccountDomain\$(($accountId -split ':', 2)[1].Trim())"
$taskPassword = ($accountPass -split ':', 2)[1].Trim()
Write-Output "task user: $taskUser"

function Invoke-Robocopy([string]$From, [string]$To, [string[]]$Extra = @()) {
    & robocopy $From $To @Extra /NFL /NDL /NP /R:2 /W:2 | Out-Null
    if ($LASTEXITCODE -ge 8) {
        throw "robocopy $From -> $To failed with exit $LASTEXITCODE"
    }
}

# 1. タスクを止める。残ったプロセスは、BEAM Watch のものと確認できた PID だけを止める。
Write-Output 'stopping task Beam-watch'
Invoke-Command -ComputerName $Server -ScriptBlock {
    $task = Get-ScheduledTask -TaskName 'Beam-watch' -ErrorAction SilentlyContinue
    if ($task) {
        Stop-ScheduledTask -TaskName 'Beam-watch'
    }
    $deadline = (Get-Date).AddSeconds(30)
    do {
        $procs = @(Get-CimInstance Win32_Process | Where-Object {
                ($_.Name -eq 'erl.exe' -and $_.CommandLine -like '*beam_watch@@main*') -or
                ($_.Name -eq 'pwsh.exe' -and $_.CommandLine -like '*Start-BeamWatch.ps1*') -or
                ($_.Name -eq 'msedge.exe' -and $_.CommandLine -like '*bw-edge-*')
            })
        if ($procs.Count -eq 0) { break }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)
    foreach ($proc in $procs) {
        Write-Output "stopping leftover $($proc.Name) pid $($proc.ProcessId)"
        Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 2
    if (Get-NetTCPConnection -LocalPort 8010 -State Listen -ErrorAction SilentlyContinue) {
        throw 'port 8010 is still listening after stopping Beam-watch'
    }
    Write-Output 'stopped; port 8010 is free'
}

# 2. バックアップ（タスク停止中に取る）
foreach ($name in 'shipment', 'gui', 'deploy', 'data') {
    $from = Join-Path $uncRoot $name
    if (Test-Path -LiteralPath $from) {
        $to = Join-Path $uncRoot "$name.bak-$stamp"
        Write-Output "backup $name -> $name.bak-$stamp"
        Invoke-Robocopy $from $to @('/E')
    }
}

# 3. 配置
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
    Invoke-Robocopy $OtpSource "$uncRoot\runtime\otp" @('/E', '/XD', 'doc')
} else {
    Write-Output 'OTP already present'
}

Write-Output 'copying shipment'
Invoke-Robocopy $shipment "$uncRoot\shipment" @('/MIR')

Copy-Item -LiteralPath (Join-Path $projectRoot 'gui\index.html') -Destination "$uncRoot\gui\index.html" -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'gui\script.js') -Destination "$uncRoot\gui\script.js" -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'gui\style.css') -Destination "$uncRoot\gui\style.css" -Force
foreach ($script in 'Start-BeamWatch.ps1', 'Register-BeamWatchTask.ps1', 'BrowserCheck.ps1', 'Grant-BatchLogonRight.ps1') {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "server\$script") -Destination "$uncRoot\deploy\$script" -Force
}

$remoteSettings = "$uncRoot\gui\settings.json"
if (-not (Test-Path -LiteralPath $remoteSettings)) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'ai195417-settings.json') -Destination $remoteSettings -Force
    Write-Output 'settings.json created'
} else {
    Write-Output 'settings.json already exists and was left as-is'
}

# 4〜6. 権利の付与、タスク登録、起動
Invoke-Command -ComputerName $Server -ArgumentList $taskUser, $taskPassword -ScriptBlock {
    param($user, $password)
    $pwsh = 'C:\Program Files\PowerShell\7\pwsh.exe'
    $deploy = 'C:\server\Apps\beam-watch\deploy'

    & $pwsh -NoProfile -ExecutionPolicy Bypass -File "$deploy\Grant-BatchLogonRight.ps1" -Account $user
    if ($LASTEXITCODE -ne 0) {
        throw "Grant-BatchLogonRight.ps1 exited with $LASTEXITCODE"
    }

    $env:BW_TASK_PASSWORD = $password
    try {
        & $pwsh -NoProfile -ExecutionPolicy Bypass -File "$deploy\Register-BeamWatchTask.ps1" -TaskUser $user
        if ($LASTEXITCODE -ne 0) {
            throw "Register-BeamWatchTask.ps1 exited with $LASTEXITCODE"
        }
    }
    finally {
        Remove-Item Env:\BW_TASK_PASSWORD -ErrorAction SilentlyContinue
    }

    Start-ScheduledTask -TaskName 'Beam-watch'
    Write-Output 'task started'
}
Write-Output 'publish finished'
