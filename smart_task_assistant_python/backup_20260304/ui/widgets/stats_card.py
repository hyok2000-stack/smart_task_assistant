"""
统计卡片组件 - 可点击
"""

from PyQt5.QtWidgets import QFrame, QVBoxLayout, QLabel, QHBoxLayout
from PyQt5.QtCore import Qt, pyqtSignal


class StatsCard(QFrame):
    clicked = pyqtSignal(str)
    
    def __init__(self, title: str, count: int, color: str, icon: str = '', filter_key: str = ''):
        super().__init__()
        
        self.title = title
        self.color = color
        self.count = count
        self.icon = icon
        self.filter_key = filter_key
        
        self._init_ui()
    
    def _init_ui(self):
        self.setCursor(Qt.PointingHandCursor)
        self.setFixedHeight(50)
        
        self.setStyleSheet(f'''
            StatsCard {{
                background-color: white;
                border: 1px solid {self.color}33;
                border-radius: 6px;
                border-left: 3px solid {self.color};
            }}
            StatsCard:hover {{
                background-color: {self.color}11;
                border: 1px solid {self.color}55;
            }}
        ''')
        
        layout = QHBoxLayout(self)
        layout.setContentsMargins(10, 6, 10, 6)
        layout.setSpacing(8)
        
        self.title_label = QLabel(self.title)
        self.title_label.setStyleSheet('''
            QLabel {
                font-size: 11px;
                color: #666;
            }
        ''')
        layout.addWidget(self.title_label)
        
        layout.addStretch()
        
        self.count_label = QLabel(str(self.count))
        self.count_label.setStyleSheet(f'''
            QLabel {{
                font-size: 18px;
                font-weight: bold;
                color: {self.color};
            }}
        ''')
        layout.addWidget(self.count_label)
        
        if self.icon:
            icon_label = QLabel(self.icon)
            icon_label.setStyleSheet('''
                QLabel {
                    font-size: 18px;
                }
            ''')
            layout.addWidget(icon_label)
    
    def set_count(self, count: int):
        self.count = count
        self.count_label.setText(str(count))
    
    def mousePressEvent(self, event):
        if event.button() == Qt.LeftButton:
            self.clicked.emit(self.filter_key)
        super().mousePressEvent(event)
