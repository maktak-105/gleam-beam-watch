# ブラウザで URL を開き、JavaScript 実行後のページで死活を判定する。
# 標準出力は 1 行。OK、または NG と理由。
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Url
)

$ErrorActionPreference = 'Continue'
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = $OutputEncoding

function Find-Edge {
    $candidates = @(
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
    )
    foreach ($path in $candidates) {
        if (Test-Path -LiteralPath $path) { return $path }
    }
    return $null
}

function Stop-EdgeForDir([string]$DataDir) {
    $procs = Get-CimInstance Win32_Process -Filter "Name = 'msedge.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine.Contains($DataDir) }
    foreach ($proc in $procs) {
        Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
    }
}

$edge = Find-Edge
if (-not $edge) {
    Write-Output 'NG Edgeがない'
    exit 0
}

$dataDir = Join-Path $env:TEMP ('bw-edge-' + [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
$outFile = Join-Path $dataDir 'dom.html'
$errFile = Join-Path $dataDir 'edge.err'

try {
    $proc = Start-Process -FilePath $edge -ArgumentList @(
        '--headless=new',
        '--disable-gpu',
        '--no-first-run',
        '--no-default-browser-check',
        "--user-data-dir=$dataDir",
        '--virtual-time-budget=20000',
        '--timeout=30000',
        '--dump-dom',
        $Url
    ) -RedirectStandardOutput $outFile -RedirectStandardError $errFile -WindowStyle Hidden -PassThru

    if (-not $proc.WaitForExit(40000)) {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        Write-Output 'NG タイムアウト'
        exit 0
    }

    $html = ''
    if (Test-Path -LiteralPath $outFile) {
        $html = Get-Content -LiteralPath $outFile -Raw -ErrorAction SilentlyContinue
    }
    if (-not $html -or $html.Length -lt 40) {
        Write-Output 'NG ページを取得できない'
        exit 0
    }
    if ($html -match 'Vercel Security Checkpoint' -or $html -match "We're verifying your browser") {
        Write-Output 'NG ブラウザ確認を通過できない'
        exit 0
    }
    if ($html -match 'Just a moment' -and $html -match 'Cloudflare') {
        Write-Output 'NG ブラウザ確認を通過できない'
        exit 0
    }
    Write-Output 'OK'
}
finally {
    Stop-EdgeForDir $dataDir
    Remove-Item -LiteralPath $dataDir -Recurse -Force -ErrorAction SilentlyContinue
}
