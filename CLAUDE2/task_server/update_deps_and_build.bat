@echo off
chcp 65001 >nul
echo ====================================
echo Task Server - 更新依赖并编译
echo ====================================
echo.

echo [1/4] 检查 Go 环境...
where go >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo 错误: 未找到 Go 命令！
    echo 请确保已安装 Go 并将其添加到系统 PATH 环境变量中。
    echo.
    echo 安装指南: https://golang.org/doc/install
    pause
    exit /b 1
)
echo Go 环境检查通过.
echo.

echo [2/4] 更新依赖 (go mod tidy)...
echo 正在下载依赖包，这可能需要几分钟时间...
go mod tidy
if %ERRORLEVEL% NEQ 0 (
    echo 依赖更新失败！错误代码: %ERRORLEVEL%
    echo.
    echo 请检查网络连接，然后重试。
    pause
    exit /b %ERRORLEVEL%
)
echo 依赖更新成功！
echo.

echo [3/4] 清理旧的可执行文件...
if exist bin\task_server.exe del /F /Q bin\task_server.exe
echo 完成.
echo.

echo [4/4] 编译新版本...
go build -o bin\task_server.exe cmd/server/main.go
if %ERRORLEVEL% NEQ 0 (
    echo 编译失败！错误代码: %ERRORLEVEL%
    pause
    exit /b %ERRORLEVEL%
)
echo 编译成功！
echo.

echo ====================================
echo 编译完成！
echo ====================================
echo.
echo 现在可以运行以下命令启动服务:
echo .\bin\task_server.exe
echo.
echo 或者按任意键直接启动服务...
pause >nul

.\bin\task_server.exe