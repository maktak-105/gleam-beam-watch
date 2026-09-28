# Gleamを自動インストールするPowerShellスクリプト

Write-Host "Gleamをインストールしています..."

try {
    # インストール先ディレクトリを作成
    $installDir = "$env:USERPROFILE\tools\gleam"
    if (!(Test-Path $installDir)) {
        New-Item -ItemType Directory -Path $installDir -Force
        Write-Host "インストールディレクトリを作成しました: $installDir"
    }

    # GitHub APIから最新のリリース情報を取得
    Write-Host "最新バージョンを検索しています..."
    $latestRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/gleam-lang/gleam/releases/latest"
    
    # Windows用のバイナリURLを取得
    $downloadUrl = $latestRelease.assets | Where-Object { $_.name -like "*windows*" -and $_.name -like "*.zip" } | Select-Object -First 1 -ExpandProperty browser_download_url
    
    if (-not $downloadUrl) {
        throw "Windows用のバイナリが見つかりません"
    }
    
    Write-Host "ダウンロードURL: $downloadUrl"
    
    # ダウンロードファイルのパスを設定
    $zipPath = "$env:TEMP\gleam.zip"
    
    # 最新のGleamをダウンロード
    Write-Host "Gleamの最新バージョンをダウンロードしています..."
    Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath
    
    # ダウンロードしたZIPファイルを展開
    Write-Host "ZIPファイルを展開しています..."
    Expand-Archive -Path $zipPath -DestinationPath $installDir -Force
    
    # PATHに追加
    $currentPath = [Environment]::GetEnvironmentVariable("PATH", [EnvironmentVariableTarget]::User)
    if ($currentPath -notlike "*$installDir*") {
        [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$installDir", [EnvironmentVariableTarget]::User)
        Write-Host "PATHに追加しました: $installDir"
    }
    
    # インストール確認
    Write-Host "Gleamのインストールが完了しました。"
    Write-Host "新しいターミナルを開いて、'gleam --version'を実行してください。"
    
    # ダウンロードファイルを削除
    Remove-Item $zipPath -Force
    
    Write-Host "インストールが完了しました！"
}
catch {
    Write-Error "インストール中にエラーが発生しました: $($_.Exception.Message)"
}