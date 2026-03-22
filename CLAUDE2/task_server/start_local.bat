@echo off
chcp 65001 >nul
echo ========================================
echo   智能任务中心后台服务 - 本地启动
echo ========================================
echo.

REM 检查 Go 是否安装
where go >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo [错误] 未检测到 Go 环境
    echo 请先安装 Go: https://golang.org/dl/
    pause
    exit /b 1
)

echo [√] Go 环境检测通过
echo.

REM 进入项目目录
cd /d "%~dp0"
echo [√] 当前目录: %CD%
echo.

REM 检查配置文件
if not exist "configs\.env.local" (
    echo [错误] 未找到本地配置文件
    echo 请确保 configs\.env.local 文件存在
    pause
    exit /b 1
)

echo [√] 配置文件检测通过
echo.

REM 创建数据目录
if not exist "data" (
    mkdir data
    echo [√] 创建数据目录
)

REM 检查依赖
echo [1/3] 检查项目依赖...
go mod tidy
if %ERRORLEVEL% neq 0 (
    echo [错误] 依赖安装失败
    pause
    exit /b 1
)
echo [√] 依赖检查完成
echo.

REM 构建项目
echo [2/3] 构建项目...
go build -o bin/task_server.exe cmd/server/main.go
if %ERRORLEVEL% neq 0 (
    echo [错误] 项目构建失败
    pause
    exit /b 1
)
echo [√] 项目构建完成
echo.

REM 启动服务
echo [3/3] 启动服务...
echo ========================================
echo 服务启动中...
echo 访问地址: http://localhost:8080
echo 健康检查: http://localhost:8080/health
echo API 文档: http://localhost:8080/api/v1
echo ========================================
echo.
echo 按 Ctrl+C 停止服务
echo.

bin\task_server.exe

pause