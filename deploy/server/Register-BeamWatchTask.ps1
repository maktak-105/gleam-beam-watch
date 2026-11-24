# サーバー上で実行する。
# 常駐タスク Beam-watch と、bunai-server の PostgreSQL 規則と同じ3範囲・Domain の
# 受信許可 (TCP 8010) を登録する。何度実行しても同じ結果になる。
# 既存の他タスク・他ファイアウォール規則には触れない。
[CmdletBinding()]
param(
    [int]$Port = 8010,
    [string]$PwshPath = 'C:\Program Files\PowerShell\7\pwsh.exe'
)

$ErrorActionPreference = 'Stop'
$appRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$starter = Join-Path $PSScriptRoot 'Start-BeamWatch.ps1'

if (-not (Test-Path -LiteralPath $PwshPath -PathType Leaf)) {
    throw "pwsh was not found: $PwshPath"
}
if (-not (Test-Path -LiteralPath $starter -PathType Leaf)) {
    throw "Start-BeamWatch.ps1 was not found: $starter"
}

$taskName = 'Beam-watch'
$action = New-ScheduledTaskAction -Execute $PwshPath -WorkingDirectory $appRoot `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$starter`""
$trigger = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -RestartCount 5 -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -StartWhenAvailable `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings `
    -Principal $principal -Description 'BEAM Watch GUI on AI195417 (deploy/server/Register-BeamWatchTask.ps1)' -Force | Out-Null
Write-Output "task registered: $taskName"

$ruleName = "BEAM Watch (TCP $Port)"
$existingRule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
if ($existingRule) {
    Write-Output "firewall rule exists: $ruleName"
} else {
    # bunai-server の PostgreSQL 5432 規則と同じ。本社LAN、社内Wi-Fi、事務所。
    New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Action Allow -Protocol TCP `
        -LocalPort $Port -Profile Domain `
        -RemoteAddress '172.26.208.0/20', '10.178.32.0/20', '160.203.88.0/24' | Out-Null
    Write-Output "firewall rule created: $ruleName"
}
