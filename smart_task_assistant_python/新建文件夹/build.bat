@echo off
chcp 65001
echo ========================================
echo   智能任务助手 - 打包脚本
echo ========================================
echo.

echo 正在检查PyInstaller...
python -m PyInstaller --version >nul 2>&1
if %errorlevel% neq 0 (
    echo 正在安装PyInstaller...
    python -m pip install pyinstaller
)

echo.
echo 正在打包程序...
python -m PyInstaller --noconfirm --onefile --windowed --name "SmartTaskAssistant" --add-data "ui;ui" --add-data "core;core" main.py

echo.
if exist "dist\SmartTaskAssistant.exe" (
    echo ========================================
    echo 打包完成！
    echo 输出文件: dist\SmartTaskAssistant.exe
    echo ========================================
    echo.
    echo 您可以将该exe文件分发给其他用户使用
) else (
    echo 打包失败，请检查错误信息
)

pause
