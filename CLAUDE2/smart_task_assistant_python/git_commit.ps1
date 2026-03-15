# Git 提交脚本
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Git 版本管理初始化" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 设置编码
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# 进入项目目录
Set-Location -Path $PSScriptRoot

Write-Host "当前目录：$(Get-Location)" -ForegroundColor Yellow
Write-Host ""

# 配置用户信息
Write-Host "[1/3] 配置用户信息..." -ForegroundColor Green
git config user.name "Developer"
git config user.email "dev@example.com"
Write-Host "用户信息已配置" -ForegroundColor Green
Write-Host ""

# 提交代码
Write-Host "[2/3] 提交代码..." -ForegroundColor Green
git commit -m "Initial commit: Smart Task Assistant v1.0.0"
Write-Host "代码已提交" -ForegroundColor Green
Write-Host ""

# 创建版本标签
Write-Host "[3/3] 创建版本标签 v1.0.0..." -ForegroundColor Green
git tag -a v1.0.0 -m "Initial release"
Write-Host "版本标签已创建" -ForegroundColor Green
Write-Host ""

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Git 初始化完成！" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "查看提交历史：git log" -ForegroundColor Yellow
Write-Host "查看状态：git status" -ForegroundColor Yellow
Write-Host ""
Write-Host "后续操作建议：" -ForegroundColor Cyan
Write-Host "1. 创建 GitHub/Gitee 仓库" -ForegroundColor White
Write-Host "2. 添加远程仓库：git remote add origin <仓库地址>" -ForegroundColor White
Write-Host "3. 推送代码：git push -u origin main" -ForegroundColor White
Write-Host ""

Pause
