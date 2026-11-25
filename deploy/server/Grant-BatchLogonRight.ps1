# サーバー上で、管理者として実行する。
# 指定アカウントに「バッチジョブとしてログオン」(SeBatchLogonRight) を足す。
# タスク Beam-watch をそのアカウントのパスワード保存で動かすために要る。
# 先に今のユーザー権利を書き出して残す。足すのはこの1アカウントだけで、ほかの権利は変えない。
# 何度実行しても同じ結果になる。
#
# 元に戻す: secedit /configure /db <一時.sdb> /cfg <バックアップ.inf> /areas USER_RIGHTS
[CmdletBinding()]
param(
    [string]$Account = 'GLOBAL\AAdmZ100DB110',
    [string]$BackupDir = 'C:\server\Apps\beam-watch\deploy'
)

$ErrorActionPreference = 'Stop'

function Export-UserRights([string]$Path) {
    & secedit.exe /export /cfg $Path /areas USER_RIGHTS /quiet | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $Path)) {
        throw "secedit /export failed with exit $LASTEXITCODE"
    }
}

function Get-BatchLine([string[]]$Lines) {
    return $Lines | Where-Object { $_ -match '^\s*SeBatchLogonRight\s*=' } | Select-Object -First 1
}

$sid = ([System.Security.Principal.NTAccount]$Account).Translate([System.Security.Principal.SecurityIdentifier]).Value
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$work = Join-Path $env:TEMP "bw-user-rights-$stamp"
New-Item -ItemType Directory -Path $work -Force | Out-Null

try {
    $current = Join-Path $work 'current.inf'
    Export-UserRights $current
    $lines = Get-Content -LiteralPath $current -Encoding Unicode
    $batch = Get-BatchLine $lines

    if ($batch -and ($batch -split '=', 2)[1].Split(',').Trim() -contains "*$sid") {
        Write-Output "already granted: $Account ($sid)"
        return
    }

    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    $backup = Join-Path $BackupDir "user-rights-backup-$stamp.inf"
    Copy-Item -LiteralPath $current -Destination $backup
    Write-Output "backup: $backup"

    if ($batch) {
        $lines = $lines | ForEach-Object {
            if ($_ -eq $batch) { "$($_.TrimEnd()),*$sid" } else { $_ }
        }
    } else {
        $index = [Array]::IndexOf($lines, ($lines | Where-Object { $_ -match '^\[Privilege Rights\]' } | Select-Object -First 1))
        if ($index -lt 0) { throw '[Privilege Rights] was not found in the exported policy' }
        $lines = @($lines[0..$index]) + @("SeBatchLogonRight = *$sid") + @($lines[($index + 1)..($lines.Count - 1)])
    }

    $updated = Join-Path $work 'updated.inf'
    Set-Content -LiteralPath $updated -Value $lines -Encoding Unicode
    & secedit.exe /configure /db (Join-Path $work 'apply.sdb') /cfg $updated /areas USER_RIGHTS /quiet | Out-Null
    # secedit は警告があると 0 以外を返す（2026-11-25、反映済みなのに 0 以外だった）。
    # 成否は終了コードではなく、下の書き出し直しで確かめる。
    if ($LASTEXITCODE -ne 0) {
        Write-Output "secedit /configure exit $LASTEXITCODE (checking the result)"
    }

    $verify = Join-Path $work 'verify.inf'
    Export-UserRights $verify
    $after = Get-BatchLine (Get-Content -LiteralPath $verify -Encoding Unicode)
    if (-not ($after -and ($after -split '=', 2)[1].Split(',').Trim() -contains "*$sid")) {
        throw "SeBatchLogonRight does not contain $Account after configure: $after"
    }
    Write-Output "granted: $Account ($sid)"
    Write-Output "now: $($after.Trim())"
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
