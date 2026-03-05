@echo off
echo ========================================
echo Git 版本管理初始化脚本
echo ========================================
echo.

cd /d "%~dp0"

echo 当前目录：%CD%
echo.

echo [1/4] 检查 Git 版本...
git --version
echo.

echo [2/4] 配置用户信息...
git config user.name "Developer"
git config user.email "dev@example.com"
echo 用户信息已配置
echo.

echo [3/4] 添加所有文件到 Git...
git add .
echo 文件已添加
echo.

echo [4/4] 提交代码...
git commit -m "Initial commit: Smart Task Assistant v1.0.0"
echo.

echo ========================================
echo 创建版本标签...
git tag -a v1.0.0 -m "Initial release"
echo.

echo ========================================
echo Git 初始化完成！
echo ========================================
echo.
echo 查看提交历史：git log
echo 查看状态：git status
echo 创建远程仓库后推送：git push -u origin main
echo.
pause
