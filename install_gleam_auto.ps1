# Gleamを自動インストールするPowerShellスクリプト

# 管理者権限で実行する必要があります

# Gleamの最新バージョンURL
$gleamUrl = "https://github.com/gleam-lang/gleam/releases/latest/download/gleam-windows-amd64.zip"

# 一時フォルダを作成
$tempDir = "$env:TEMP\gleam_install"
if (!(Test-Path $tempDir)) {
    New-Item -ItemType Directory -Path $tempDir
}

# ダウンロード先のパス
$zipPath = "$tempDir\gleam.zip"

try {
    # GleamのZIPファイルをダウンロード
    Write-Host "Gleamをダウンロード中..."
    Invoke-WebRequest -Uri $gleamUrl -OutFile $zipPath
    
    # ZIPファイルを展開
    Write-Host "ZIPファイルを展開中..."
    Expand-Archive -Path $zipPath -DestinationPath $tempDir -Force
    
    # gleam.exeのパスを取得
    $gleamExe = "$tempDir\gleam.exe"
    
    if (Test-Path $gleamExe) {
        # gleam.exeをシステムフォルダにコピー
        $systemPath = "C:\tools\gleam"
        if (!(Test-Path $systemPath)) {
            New-Item -ItemType Directory -Path $systemPath
        }
        
        Copy-Item -Path $gleamExe -Destination "$systemPath\gleam.exe"
        
        # 環境変数PATHに追加
        $currentPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
        if ($currentPath -notlike "*C:\tools\gleam*") {
            [Environment]::SetEnvironmentVariable("PATH", $currentPath + ";C:\tools\gleam", "Machine")
        }
        
        Write-Host "Gleamのインストールが完了しました！"
        Write-Host "ターミナルを再起動して、'gleam --version'コマンドで確認してください。"
    } else {
        Write-Error "gleam.exeが見つかりません。"
    }
} catch {
    Write-Error "インストール中にエラーが発生しました: $($_.Exception.Message)"
} finally {
    # 一時ファイルを削除
    Remove-Item -Path $tempDir -Recurse -Force
}