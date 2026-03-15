"""
智能任务助手 - Python桌面版
主入口文件 - 毛玻璃风格APP
"""

import sys
import os

def get_resource_path(relative_path):
    """获取资源文件路径，兼容开发环境和PyInstaller打包环境"""
    if hasattr(sys, '_MEIPASS'):
        return os.path.join(sys._MEIPASS, relative_path)
    return os.path.join(os.path.abspath("."), relative_path)

sys.path.insert(0, get_resource_path(''))

from PyQt5.QtWidgets import QApplication
from PyQt5.QtCore import Qt
from PyQt5.QtGui import QFont

# 使用毛玻璃风格主窗口
from glass_app.ui.glass_window import GlassMainWindow
from core.database import DatabaseManager
from core.config import Config

def main():
    # 启用高DPI支持
    QApplication.setAttribute(Qt.AA_EnableHighDpiScaling, True)
    QApplication.setAttribute(Qt.AA_UseHighDpiPixmaps, True)
    
    app = QApplication(sys.argv)
    app.setApplicationName('智能任务助手')
    app.setApplicationVersion('2.0.0')
    
    # 设置字体
    font = QFont('Microsoft YaHei', 10)
    app.setFont(font)
    
    # 初始化数据库和配置
    config = Config()
    db = DatabaseManager(config.db_path)
    db.init_database()
    
    # 创建并显示毛玻璃风格主窗口
    window = GlassMainWindow(db, config)
    window.show()
    
    sys.exit(app.exec_())

if __name__ == '__main__':
    main()