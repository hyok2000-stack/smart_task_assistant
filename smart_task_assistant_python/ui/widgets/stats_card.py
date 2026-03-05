"""
统计卡片组件
"""

from PyQt5.QtWidgets import QFrame, QVBoxLayout, QLabel, QHBoxLayout
from PyQt5.QtCore import Qt, pyqtSignal
from PyQt5.QtGui import QFont


class StatsCard(QFrame):
    clicked = pyqtSignal(str)
    
    def __init__(self, title: str, count: int, color: str, icon: str = '', filter_key: str = ''):
        super().__init__()
        
        self.title = title
        self.color = color
        self.count = count
        self.icon = icon
        self.filter_key = filter_key
        self._selected = False
        
        self._init_ui()
    
    def _init_ui(self):
        self.setCursor(Qt.PointingHandCursor)
        self.setFixedHeight(50)
        
        self._update_style()
        
        layout = QHBoxLayout(self)
        layout.setContentsMargins(12, 8, 12, 8)
        layout.setSpacing(8)
        
        if self.icon:
            icon_label = QLabel(self.icon)
            icon_label.setStyleSheet('font-size: 18px;')
            layout.addWidget(icon_label)
        
        self.title_label = QLabel(self.title)
        self.title_label.setStyleSheet('font-size: 12px; color: #666;')
        layout.addWidget(self.title_label)
        
        layout.addStretch()
        
        self.count_label = QLabel(str(self.count))
        self.count_label.setFont(QFont('Microsoft YaHei', 16, QFont.Bold))
        self.count_label.setStyleSheet(f'color: {self.color};')
        layout.addWidget(self.count_label)
    
    def _update_style(self):
        if self._selected:
            self.setStyleSheet(f'''
                StatsCard {{
                    background-color: white;
                    border: 2px solid {self.color};
                    border-radius: 6px;
                    border-left: 4px solid {self.color};
                }}
            ''')
        else:
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
    
    def set_selected(self, selected: bool):
        self._selected = selected
        self._update_style()
    
    def is_selected(self) -> bool:
        return self._selected
    
    def set_count(self, count: int):
        self.count = count
        self.count_label.setText(str(count))
    
    def mousePressEvent(self, event):
        if event.button() == Qt.LeftButton:
            self.clicked.emit(self.filter_key)
        super().mousePressEvent(event)
