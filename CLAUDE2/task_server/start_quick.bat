@echo off
chcp 65001 >nul
echo ========================================
echo   智能任务中心后台服务 - 快速启动
echo ========================================
echo.

REM 进入项目目录
cd /d "%~dp0"

REM 检查可执行文件
if not exist "bin\task_server.exe" (
    echo [错误] 未找到可执行文件
    echo 请先运行 start_local.bat 进行构建
    pause
    exit /b 1
)

REM 创建数据目录
if not exist "data" (
    mkdir data
    echo [√] 创建数据目录
)

echo [√] 启动服务...
echo ========================================
echo 访问地址: http://localhost:8080
echo 健康检查: http://localhost:8080/health
echo API 文档: http://localhost:8080/api/v1
echo ========================================
echo.
echo 按 Ctrl+C 停止服务
echo.

bin\task_server.exe

pause