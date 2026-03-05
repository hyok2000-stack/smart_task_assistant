"""
关于对话框 - 版权说明
"""

from PyQt5.QtWidgets import (
    QDialog, QVBoxLayout, QHBoxLayout, QLabel, QPushButton, QFrame, QScrollArea, QWidget, QGridLayout
)
from PyQt5.QtCore import Qt
from PyQt5.QtGui import QFont


class AboutDialog(QDialog):
    def __init__(self, parent=None):
        super().__init__(parent)
        
        self.setWindowTitle('关于 - 智能任务助手')
        self.setMinimumSize(550, 650)
        self.setModal(True)
        
        self._init_ui()
    
    def _init_ui(self):
        self.setStyleSheet('''
            QDialog {
                background-color: white;
            }
            QLabel {
                color: #333;
            }
        ''')
        
        main_layout = QVBoxLayout(self)
        main_layout.setSpacing(0)
        main_layout.setContentsMargins(0, 0, 0, 0)
        
        header_frame = QFrame()
        header_frame.setStyleSheet('background-color: white; padding: 20px;')
        header_layout = QVBoxLayout(header_frame)
        
        title_label = QLabel('智能任务助手')
        title_label.setFont(QFont('Microsoft YaHei', 24, QFont.Bold))
        title_label.setStyleSheet('color: #1976D2;')
        title_label.setAlignment(Qt.AlignCenter)
        header_layout.addWidget(title_label)
        
        version_label = QLabel('V1.0.0  |  2026年3月')
        version_label.setFont(QFont('Microsoft YaHei', 12))
        version_label.setStyleSheet('color: #666;')
        version_label.setAlignment(Qt.AlignCenter)
        header_layout.addWidget(version_label)
        
        main_layout.addWidget(header_frame)
        
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setStyleSheet('''
            QScrollArea {
                border: none;
                background-color: white;
            }
            QScrollBar:vertical {
                width: 8px;
                background-color: #f0f0f0;
            }
            QScrollBar::handle:vertical {
                background-color: #ccc;
                border-radius: 4px;
                min-height: 30px;
            }
            QScrollBar::handle:vertical:hover {
                background-color: #999;
            }
        ''')
        
        scroll_content = QWidget()
        scroll_layout = QVBoxLayout(scroll_content)
        scroll_layout.setSpacing(12)
        scroll_layout.setContentsMargins(25, 10, 25, 20)
        
        info_frame = QFrame()
        info_frame.setStyleSheet('''
            QFrame {
                background-color: #F5F5F5;
                border-radius: 8px;
                padding: 10px;
            }
        ''')
        info_layout = QVBoxLayout(info_frame)
        
        info_items = [
            ('开发单位', '湖南高速信息科技有限公司'),
            ('开发人员', '黄勇（数字信息事业部）'),
            ('开发工具', 'TRAE AI智能体编程工具、GLM5大模型'),
            ('开发方式', 'AI全程自主编程、自主排错'),
        ]
        
        for label, value in info_items:
            item_layout = QHBoxLayout()
            label_widget = QLabel(f'{label}：')
            label_widget.setStyleSheet('color: #666; font-weight: bold;')
            label_widget.setFixedWidth(80)
            item_layout.addWidget(label_widget)
            
            value_widget = QLabel(value)
            value_widget.setStyleSheet('color: #333;')
            item_layout.addWidget(value_widget, 1)
            
            info_layout.addLayout(item_layout)
        
        scroll_layout.addWidget(info_frame)
        
        stats_label = QLabel('📊 开发统计')
        stats_label.setFont(QFont('Microsoft YaHei', 14, QFont.Bold))
        stats_label.setStyleSheet('color: #1976D2; margin-top: 10px;')
        scroll_layout.addWidget(stats_label)
        
        stats_frame = QFrame()
        stats_frame.setStyleSheet('''
            QFrame {
                background-color: #E3F2FD;
                border-radius: 8px;
                padding: 10px;
            }
        ''')
        stats_layout = QVBoxLayout(stats_frame)
        
        stats_items = [
            ('开发工时', '约 8 小时'),
            ('功能模块', '12 个'),
            ('需求优化', '35+ 项'),
            ('BUG自主修复', '28+ 个'),
        ]
        
        stats_row = QHBoxLayout()
        for label, value in stats_items:
            stat_widget = QLabel(f'{value}\n{label}')
            stat_widget.setAlignment(Qt.AlignCenter)
            stat_widget.setStyleSheet('''
                QLabel {
                    color: #1976D2;
                    font-weight: bold;
                    padding: 8px;
                }
            ''')
            stats_row.addWidget(stat_widget)
        
        stats_layout.addLayout(stats_row)
        scroll_layout.addWidget(stats_frame)
        
        highlight_label = QLabel('🚀 技术亮点')
        highlight_label.setFont(QFont('Microsoft YaHei', 14, QFont.Bold))
        highlight_label.setStyleSheet('color: #1976D2; margin-top: 10px;')
        scroll_layout.addWidget(highlight_label)
        
        highlights = [
            ('AI自主编程', '全程由TRAE AI智能体根据需求自动生成代码，无需人工编写'),
            ('AI自主排错', 'AI自动检测运行错误并自主修复，实现零人工调试'),
            ('高效交付', '传统开发需数周的项目，AI仅用8小时完成'),
        ]
        
        for title, desc in highlights:
            h_layout = QHBoxLayout()
            h_icon = QLabel('✨')
            h_icon.setStyleSheet('font-size: 16px;')
            h_layout.addWidget(h_icon)
            
            h_text = QLabel(f'<b>{title}</b> - {desc}')
            h_text.setWordWrap(True)
            h_text.setStyleSheet('color: #333;')
            h_layout.addWidget(h_text, 1)
            
            scroll_layout.addLayout(h_layout)
        
        func_label = QLabel('🎯 功能亮点')
        func_label.setFont(QFont('Microsoft YaHei', 14, QFont.Bold))
        func_label.setStyleSheet('color: #1976D2; margin-top: 10px;')
        scroll_layout.addWidget(func_label)
        
        features = [
            'AI智能任务识别',
            '剪贴板自动监听',
            '智答AI对话咨询',
            '托盘提醒通知',
            '多维度筛选统计',
            '外部系统对接',
        ]
        
        features_frame = QFrame()
        features_frame.setStyleSheet('''
            QFrame {
                background-color: #F5F5F5;
                border-radius: 8px;
                padding: 10px;
            }
        ''')
        features_grid = QGridLayout(features_frame)
        features_grid.setSpacing(10)
        
        for i, feature in enumerate(features):
            row = i // 2
            col = i % 2
            
            f_widget = QLabel(f'✅ {feature}')
            f_widget.setStyleSheet('color: #333; padding: 5px;')
            features_grid.addWidget(f_widget, row, col)
        
        scroll_layout.addWidget(features_frame)
        
        scroll_layout.addStretch()
        
        line2 = QFrame()
        line2.setFrameShape(QFrame.HLine)
        line2.setStyleSheet('background-color: #E0E0E0;')
        scroll_layout.addWidget(line2)
        
        copyright_label = QLabel('本软件由湖南高速信息科技有限公司数字信息事业部黄勇开发，\n使用TRAE AI智能体全程自主编程完成。未经授权，不得用于商业用途。')
        copyright_label.setAlignment(Qt.AlignCenter)
        copyright_label.setStyleSheet('color: #999; font-size: 11px; margin-top: 10px;')
        copyright_label.setWordWrap(True)
        scroll_layout.addWidget(copyright_label)
        
        scroll.setWidget(scroll_content)
        main_layout.addWidget(scroll, 1)
        
        btn_frame = QFrame()
        btn_frame.setStyleSheet('background-color: white; padding: 15px;')
        btn_layout = QHBoxLayout(btn_frame)
        btn_layout.addStretch()
        
        close_btn = QPushButton('确定')
        close_btn.setFixedWidth(100)
        close_btn.setStyleSheet('''
            QPushButton {
                background-color: #2196F3;
                color: white;
                border: none;
                padding: 8px 20px;
                border-radius: 6px;
                font-weight: bold;
            }
            QPushButton:hover {
                background-color: #1976D2;
            }
        ''')
        close_btn.clicked.connect(self.accept)
        btn_layout.addWidget(close_btn)
        btn_layout.addStretch()
        
        main_layout.addWidget(btn_frame)
