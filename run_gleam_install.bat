@echo off
:: Gleamインストールスクリプトを管理者権限で実行するバッチファイル

echo このスクリプトはGleamをインストールします。
echo.

:: 管理者権限で実行されているか確認
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo 管理者権限で実行する必要があります。
    echo 管理者権限でこのバッチファイルを実行してください。
    pause
    exit /b
)

echo 管理者権限で実行中...
echo.

:: PowerShellスクリプトを実行
powershell -ExecutionPolicy Bypass -File "%~dp0install_gleam_auto.ps1"

echo.
echo インストールが完了しました。
pause