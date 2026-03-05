"""
任务卡片组件 - 带优先级分类显示
"""

from datetime import datetime
from PyQt5.QtWidgets import QFrame, QVBoxLayout, QHBoxLayout, QLabel, QPushButton
from PyQt5.QtCore import Qt, pyqtSignal


class TaskCardWidget(QFrame):
    delete_requested = pyqtSignal(str)
    
    def __init__(self, task: dict):
        super().__init__()
        
        self.task = task
        self._init_ui()
    
    def _init_ui(self):
        status = self.task.get('status', 'pending')
        priority = self.task.get('priority', 'medium')
        
        status_styles = {
            'pending': ('待处理', '#9E9E9E', '○'),
            'in_progress': ('进行中', '#2196F3', '◐'),
            'completed': ('已完成', '#4CAF50', '●'),
            'cancelled': ('已取消', '#F44336', '✕')
        }
        
        priority_styles = {
            'high': ('高', '#F44336', '🔴'),
            'medium': ('中', '#FF9800', '🟡'),
            'low': ('低', '#4CAF50', '🟢')
        }
        
        status_text, status_color, status_icon = status_styles.get(status, ('未知', '#9E9E9E', '?'))
        priority_text, priority_color, priority_icon = priority_styles.get(priority, ('中', '#FF9800', '🟡'))
        
        is_overdue = self._is_overdue()
        
        border_color = '#E0E0E0'
        if is_overdue and status not in ['completed', 'cancelled']:
            border_color = '#F44336'
        
        self.setStyleSheet(f'''
            TaskCardWidget {{
                background-color: white;
                border: 1px solid {border_color};
                border-radius: 10px;
                border-left: 4px solid {priority_color};
            }}
            TaskCardWidget:hover {{
                border-color: #2196F3;
                background-color: #FAFAFA;
            }}
        ''')
        
        layout = QVBoxLayout(self)
        layout.setSpacing(8)
        layout.setContentsMargins(14, 10, 14, 10)
        
        header_layout = QHBoxLayout()
        
        status_label = QLabel(status_icon)
        status_label.setStyleSheet(f'color: {status_color}; font-size: 18px;')
        header_layout.addWidget(status_label)
        
        title_label = QLabel(self.task.get('title', ''))
        title_label.setStyleSheet('font-weight: bold; font-size: 14px;')
        title_label.setWordWrap(True)
        if status == 'completed':
            title_label.setStyleSheet('font-weight: bold; font-size: 14px; text-decoration: line-through; color: #999;')
        header_layout.addWidget(title_label, 1)
        
        priority_label = QLabel(f'{priority_icon} {priority_text}')
        priority_label.setStyleSheet(f'''
            QLabel {{
                color: {priority_color};
                font-size: 12px;
                font-weight: bold;
                padding: 2px 8px;
                background-color: {priority_color}22;
                border-radius: 4px;
            }}
        ''')
        header_layout.addWidget(priority_label)
        
        delete_btn = QPushButton('×')
        delete_btn.setFixedSize(24, 24)
        delete_btn.setCursor(Qt.PointingHandCursor)
        delete_btn.setStyleSheet(f'''
            QPushButton {{
                background-color: transparent;
                color: #999;
                border: none;
                font-size: 18px;
                font-weight: bold;
                border-radius: 12px;
            }}
            QPushButton:hover {{
                background-color: #F44336;
                color: white;
            }}
        ''')
        delete_btn.clicked.connect(self._on_delete_clicked)
        header_layout.addWidget(delete_btn)
        
        layout.addLayout(header_layout)
        
        info_layout = QHBoxLayout()
        
        owner_label = QLabel(f"👤 {self.task.get('owner_name', '我')}")
        owner_label.setStyleSheet('color: #666; font-size: 12px;')
        info_layout.addWidget(owner_label)
        
        deadline_str = self._format_deadline()
        deadline_color = '#F44336' if is_overdue else '#666'
        deadline_label = QLabel(f"⏰ {deadline_str}")
        deadline_label.setStyleSheet(f'color: {deadline_color}; font-size: 12px;')
        info_layout.addWidget(deadline_label)
        
        info_layout.addStretch()
        
        source_type = self.task.get('source_type', 'manual')
        source_icons = {
            'clipboard': '📋 粘贴',
            'quick_create': '⚡ 快速',
            'manual': '✏️ 手动'
        }
        source_label = QLabel(source_icons.get(source_type, '✏️ 手动'))
        source_label.setStyleSheet('color: #999; font-size: 11px;')
        info_layout.addWidget(source_label)
        
        layout.addLayout(info_layout)
        
        if is_overdue and status not in ['completed', 'cancelled']:
            overdue_label = QLabel('⚠ 已逾期')
            overdue_label.setStyleSheet('color: #F44336; font-size: 11px; font-weight: bold;')
            layout.addWidget(overdue_label)
    
    def _on_delete_clicked(self):
        self.delete_requested.emit(self.task.get('task_id', ''))
    
    def _is_overdue(self) -> bool:
        deadline = self.task.get('deadline')
        status = self.task.get('status')
        
        if not deadline or status in ['completed', 'cancelled']:
            return False
        
        try:
            if len(deadline) == 16:
                deadline_dt = datetime.strptime(deadline, '%Y-%m-%d %H:%M')
            else:
                deadline_dt = datetime.strptime(deadline, '%Y-%m-%d %H:%M:%S')
            return deadline_dt < datetime.now()
        except:
            return False
    
    def _format_deadline(self) -> str:
        deadline = self.task.get('deadline')
        if not deadline:
            return '未设置'
        
        try:
            if len(deadline) == 16:
                deadline_dt = datetime.strptime(deadline, '%Y-%m-%d %H:%M')
            else:
                deadline_dt = datetime.strptime(deadline, '%Y-%m-%d %H:%M:%S')
            now = datetime.now()
            
            if deadline_dt.date() == now.date():
                return f"今天 {deadline_dt.strftime('%H:%M')}"
            elif deadline_dt.date() == (now + __import__('datetime').timedelta(days=1)).date():
                return f"明天 {deadline_dt.strftime('%H:%M')}"
            else:
                return deadline_dt.strftime('%m月%d日 %H:%M')
        except:
            return deadline
