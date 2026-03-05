@echo off
chcp 65001 >nul
echo ========================================
echo   智能任务助手 - 打包脚本
echo ========================================
echo.

cd /d "%~dp0"

echo [1/3] 检查PyInstaller...
python -m PyInstaller --version >nul 2>&1
if %errorlevel% neq 0 (
    echo 正在安装PyInstaller...
    pip install pyinstaller -i https://pypi.tuna.tsinghua.edu.cn/simple
)

echo.
echo [2/3] 开始打包程序...
echo 这可能需要几分钟，请耐心等待...
echo.

python -m PyInstaller --noconfirm --onefile --windowed --name "智能任务助手" --add-data "ui;ui" --add-data "core;core" --hidden-import=PyQt5 --hidden-import=requests main.py

echo.
echo [3/3] 检查打包结果...
if exist "dist\智能任务助手.exe" (
    echo.
    echo ========================================
    echo   打包成功！
    echo ========================================
    echo.
    echo 输出文件: %cd%\dist\智能任务助手.exe
    echo.
    echo 您可以将该exe文件分发给其他用户使用
    echo 无需安装Python环境即可运行
    echo.
) else (
    echo.
    echo ========================================
    echo   打包失败
    echo ========================================
    echo 请检查上方的错误信息
)

echo.
pause
