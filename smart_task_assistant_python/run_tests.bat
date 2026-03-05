@echo off
chcp 65001 >nul
echo ========================================
echo 智能任务助手 - 单元测试运行脚本
echo ========================================
echo.

echo [1/3] 检查Python环境...
python --version
if errorlevel 1 (
    echo 错误: 未找到Python环境
    pause
    exit /b 1
)

echo.
echo [2/3] 安装测试依赖...
pip install pytest pytest-cov pytest-html -q

echo.
echo [3/3] 运行测试...
echo.

echo ========== 基础测试 ==========
python -m pytest tests/test_base.py -v --tb=short

echo.
echo ========== 核心模块测试 ==========
python -m pytest tests/test_core.py -v --tb=short

echo.
echo ========== 性能测试 ==========
python -m pytest tests/test_performance.py -v --tb=short -s

echo.
echo ========================================
echo 测试完成！
echo ========================================
pause
