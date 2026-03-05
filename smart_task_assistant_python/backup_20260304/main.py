"""
智能任务助手 - Python桌面版
主入口文件
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

from ui.main_window import MainWindow
from core.database import DatabaseManager
from core.config import Config

def main():
    app = QApplication(sys.argv)
    app.setApplicationName('智能任务助手')
    app.setApplicationVersion('1.0.0')
    
    font = QFont('Microsoft YaHei', 9)
    app.setFont(font)
    
    app.setStyle('Fusion')
    
    config = Config()
    db = DatabaseManager(config.db_path)
    db.init_database()
    
    window = MainWindow(db, config)
    window.show()
    
    sys.exit(app.exec_())

if __name__ == '__main__':
    main()
