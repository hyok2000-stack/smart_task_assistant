@echo off
echo ====================================
echo Task Server - 重新编译并启动
echo ====================================
echo.

echo [1/3] 清理旧的可执行文件...
if exist bin\task_server.exe del /F /Q bin\task_server.exe
echo 完成.
echo.

echo [2/3] 编译新版本...
go build -o bin\task_server.exe cmd/server/main.go
if %ERRORLEVEL% NEQ 0 (
    echo 编译失败！错误代码: %ERRORLEVEL%
    pause
    exit /b %ERRORLEVEL%
)
echo 编译成功！
echo.

echo [3/3] 启动服务...
echo ====================================
echo 服务正在启动中...
echo ====================================
echo.
.\bin\task_server.exe