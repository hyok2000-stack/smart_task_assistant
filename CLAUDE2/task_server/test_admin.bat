@echo off
chcp 65001 >nul
echo ====================================
echo 测试后台管理页面
echo ====================================
echo.

echo [1/3] 编译服务...
call update_deps_and_build.bat
if %ERRORLEVEL% NEQ 0 (
    echo 编译失败！
    pause
    exit /b %ERRORLEVEL%
)

echo.
echo [2/3] 启动服务...
echo 服务正在启动，请稍候...
start "" /B bin\task_server.exe
timeout /t 3 /nobreak >nul

echo.
echo [3/3] 打开浏览器...
start http://localhost:8080/

echo.
echo ====================================
echo 服务已启动！
echo ====================================
echo.
echo 访问地址: http://localhost:8080/
echo.
echo 注意事项:
echo 1. 首次使用需要注册账号
echo 2. 用户名至少3个字符
echo 3. 密码至少6个字符
echo 4. 邮箱格式必须正确
echo.
echo 如需停止服务，请按 Ctrl+C 或关闭此窗口
echo.
pause