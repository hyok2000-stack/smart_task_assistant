"""
智能任务助手 - 毛玻璃风格APP
简约清爽的现代UI设计
"""

import sys
import os

# 获取当前文件所在目录
current_dir = os.path.dirname(os.path.abspath(__file__))
# 父目录（smart_task_assistant_python）
parent_dir = os.path.dirname(current_dir)

# 添加路径
sys.path.insert(0, current_dir)
sys.path.insert(0, parent_dir)

from PyQt5.QtWidgets import QApplication
from PyQt5.QtCore import Qt
from PyQt5.QtGui import QFont

# 使用相对导入
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
    
    # 创建并显示主窗口
    window = GlassMainWindow(db, config)
    window.show()
    
    sys.exit(app.exec_())


if __name__ == '__main__':
    main()