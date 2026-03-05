"""
快速创建任务对话框
"""

import uuid
from datetime import datetime
from PyQt5.QtWidgets import (
    QDialog, QVBoxLayout, QHBoxLayout, QLabel, QLineEdit,
    QPushButton, QComboBox, QFormLayout, QGroupBox
)
from PyQt5.QtCore import Qt

from core.database import DatabaseManager
from core.recognition import TaskRecognitionService


class QuickCreateDialog(QDialog):
    def __init__(self, parent, db: DatabaseManager, recognition: TaskRecognitionService):
        super().__init__(parent)
        
        self.db = db
        self.recognition = recognition
        
        self.setWindowTitle('⚡ 快速创建任务')
        self.setMinimumSize(400, 200)
        
        self._init_ui()
    
    def _init_ui(self):
        layout = QVBoxLayout(self)
        layout.setSpacing(12)
        
        form_layout = QFormLayout()
        
        self.content_edit = QLineEdit()
        self.content_edit.setPlaceholderText('输入任务内容...')
        self.content_edit.setMinimumHeight(36)
        form_layout.addRow('任务内容:', self.content_edit)
        
        priority_layout = QHBoxLayout()
        
        self.priority_combo = QComboBox()
        self.priority_combo.addItems(['🟢 低优先级', '🟡 中优先级', '🔴 高优先级'])
        self.priority_combo.setCurrentIndex(1)
        priority_layout.addWidget(self.priority_combo)
        
        priority_layout.addStretch()
        form_layout.addRow('优先级:', priority_layout)
        
        layout.addLayout(form_layout)
        
        hint_label = QLabel('提示：输入内容后，AI会自动识别标题、负责人、截止时间')
        hint_label.setStyleSheet('color: #666; font-size: 11px;')
        layout.addWidget(hint_label)
        
        button_layout = QHBoxLayout()
        button_layout.addStretch()
        
        cancel_btn = QPushButton('取消')
        cancel_btn.clicked.connect(self.reject)
        button_layout.addWidget(cancel_btn)
        
        create_btn = QPushButton('创建')
        create_btn.setStyleSheet('''
            QPushButton {
                background-color: #4CAF50;
                color: white;
                border: none;
                border-radius: 6px;
                padding: 8px 20px;
                font-weight: bold;
            }
        ''')
        create_btn.clicked.connect(self._create_task)
        create_btn.setDefault(True)
        button_layout.addWidget(create_btn)
        
        layout.addLayout(button_layout)
    
    def _create_task(self):
        content = self.content_edit.text().strip()
        if not content:
            return
        
        result = self.recognition.recognize(content)
        
        priority_map = {0: 'low', 1: 'medium', 2: 'high'}
        
        task_id = f"T{uuid.uuid4().hex[:8].upper()}"
        now = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        
        task = {
            'task_id': task_id,
            'title': result.get('title') or content[:50],
            'content': content,
            'owner_name': result.get('owner_name', '我'),
            'deadline': result.get('deadline', now[:10] + ' 18:00:00'),
            'status': 'pending',
            'priority': priority_map[self.priority_combo.currentIndex()],
            'acceptance_criteria': result.get('acceptance_criteria', ''),
            'source_type': 'manual',
            'original_content': content,
            'created_at': now,
            'updated_at': now
        }
        
        self.db.insert_task(task)
        self.accept()
