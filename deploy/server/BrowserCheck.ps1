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

# このスクリプトが開く Edge だけが信頼する証明書の公開鍵（SHA-256 / Base64）。証明書ストアは変えない。
# 人事DB (https://ai195417:8766/) の自己署名証明書 CN=ai195417.global.aisingroup.com、有効期限 2028-11-16。
# 証明書を作り直すと公開鍵が変わり、NG（証明書が信頼されていない）になる。そのときはこの値を更新する。
$TrustedSpki = @(
    '92z2Igza78cnmXGYGQsC5yq0bO96ukZi8I2htoSH+es='
)

# Edge の標準エラーにある "Page load failed: net::ERR_..." を、NG の理由にする。
function Get-LoadFailure([string]$ErrPath) {
    if (-not (Test-Path -LiteralPath $ErrPath)) { return $null }
    $text = Get-Content -LiteralPath $ErrPath -Raw -ErrorAction SilentlyContinue
    if (-not $text) { return $null }
    $match = [regex]::Match($text, 'Page load failed: net::(ERR_[A-Z_]+)')
    if (-not $match.Success) { return $null }
    $code = $match.Groups[1].Value
    $label = switch -Regex ($code) {
        '^ERR_CONNECTION_REFUSED$' { '接続を拒否された'; break }
        '^ERR_CONNECTION_RESET$' { '接続がリセットされた'; break }
        '^ERR_CONNECTION_CLOSED$' { '接続が閉じられた'; break }
        '^ERR_(CONNECTION_)?TIMED_OUT$' { '時間切れ'; break }
        '^ERR_NAME_NOT_RESOLVED$' { '名前を解決できない'; break }
        '^ERR_ADDRESS_UNREACHABLE$' { '宛先に届かない'; break }
        '^ERR_EMPTY_RESPONSE$' { '応答が空'; break }
        '^ERR_UNSAFE_PORT$' { 'ブラウザが開かないポート'; break }
        '^ERR_CERT_COMMON_NAME_INVALID$' { '証明書の名前が一致しない'; break }
        '^ERR_CERT_DATE_INVALID$' { '証明書の有効期限外'; break }
        '^ERR_CERT_' { '証明書が信頼されていない'; break }
        default { 'ページが出ない' }
    }
    return "$label ($code)"
}

# ブラウザに出たページが HTTP のエラーページなら、そのタイトル（または見出し）を返す。
# 状態コードは見ない。ページの <title> と最初の <h1> の中身で決める。
function Get-ErrorPageTitle([string]$Html) {
    $texts = @()
    $title = [regex]::Match($Html, '(?is)<title[^>]*>(.*?)</title>')
    if ($title.Success) { $texts += $title.Groups[1].Value }
    $heading = [regex]::Match($Html, '(?is)<h1[^>]*>(.*?)</h1>')
    if ($heading.Success) { $texts += $heading.Groups[1].Value }
    foreach ($raw in $texts) {
        $text = ([System.Net.WebUtility]::HtmlDecode(($raw -replace '<[^>]+>', ' ')) -replace '\s+', ' ').Trim()
        if (-not $text) { continue }
        if ($text -match '^[45]\d\d\b' -or
            $text -match '^HTTP Error [45]\d\d' -or
            $text -match '^(Not Found|Bad Gateway|Service Unavailable|Internal Server Error|Gateway Time-?out|Server Error|Forbidden|Error response)$') {
            if ($text.Length -gt 80) { $text = $text.Substring(0, 80) }
            return $text
        }
    }
    return $null
}

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
        "--ignore-certificate-errors-spki-list=$($TrustedSpki -join ',')",
        '--virtual-time-budget=20000',
        '--timeout=30000',
        '--dump-dom',
        $Url
    ) -RedirectStandardOutput $outFile -RedirectStandardError $errFile -WindowStyle Hidden -PassThru

    if (-not $proc.WaitForExit(40000)) {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        # 読み込みに失敗したまま Edge が終わらないことがある。その場合は失敗の理由を出す。
        $failure = Get-LoadFailure $errFile
        if ($failure) {
            Write-Output "NG $failure"
        } else {
            Write-Output 'NG タイムアウト'
        }
        exit 0
    }

    $html = ''
    if (Test-Path -LiteralPath $outFile) {
        $html = Get-Content -LiteralPath $outFile -Raw -ErrorAction SilentlyContinue
    }
    if (-not $html -or $html.Length -lt 40) {
        $failure = Get-LoadFailure $errFile
        if ($failure) {
            Write-Output "NG $failure"
        } else {
            Write-Output 'NG ページを取得できない'
        }
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
    $errorPage = Get-ErrorPageTitle $html
    if ($errorPage) {
        Write-Output "NG エラーページが出た ($errorPage)"
        exit 0
    }
    Write-Output 'OK'
}
finally {
    Stop-EdgeForDir $dataDir
    Remove-Item -LiteralPath $dataDir -Recurse -Force -ErrorAction SilentlyContinue
}
