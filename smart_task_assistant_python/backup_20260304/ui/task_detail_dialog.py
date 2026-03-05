"""
任务详情对话框
"""

from datetime import datetime
from PyQt5.QtWidgets import (
    QDialog, QVBoxLayout, QHBoxLayout, QLabel, QLineEdit,
    QTextEdit, QPushButton, QComboBox, QDateTimeEdit,
    QFormLayout, QGroupBox, QMessageBox, QFrame
)
from PyQt5.QtCore import Qt, QDateTime

from core.database import DatabaseManager
from core.recognition import TaskRecognitionService


class TaskDetailDialog(QDialog):
    def __init__(self, parent, db: DatabaseManager, recognition: TaskRecognitionService, task_id: str):
        super().__init__(parent)
        
        self.db = db
        self.recognition = recognition
        self.task_id = task_id
        self.task = db.get_task_by_id(task_id)
        
        if not self.task:
            QMessageBox.warning(parent, '错误', '任务不存在')
            self.reject()
            return
        
        self._init_ui()
        self._load_task()
    
    def _init_ui(self):
        self.setWindowTitle('任务详情')
        self.setMinimumSize(500, 550)
        
        layout = QVBoxLayout(self)
        
        header_layout = QHBoxLayout()
        
        self.status_label = QLabel()
        self.status_label.setStyleSheet('''
            QLabel {
                padding: 4px 12px;
                border-radius: 4px;
                font-weight: bold;
            }
        ''')
        header_layout.addWidget(self.status_label)
        
        self.priority_label = QLabel()
        self.priority_label.setStyleSheet('''
            QLabel {
                padding: 4px 12px;
                border-radius: 4px;
            }
        ''')
        header_layout.addWidget(self.priority_label)
        
        header_layout.addStretch()
        
        layout.addLayout(header_layout)
        
        form_group = QGroupBox('任务信息')
        form_layout = QFormLayout(form_group)
        
        self.title_edit = QLineEdit()
        form_layout.addRow('标题:', self.title_edit)
        
        self.owner_edit = QLineEdit()
        form_layout.addRow('负责人:', self.owner_edit)
        
        self.deadline_edit = QDateTimeEdit()
        self.deadline_edit.setCalendarPopup(True)
        form_layout.addRow('截止时间:', self.deadline_edit)
        
        self.status_combo = QComboBox()
        self.status_combo.addItems(['待处理', '进行中', '已完成', '已取消'])
        form_layout.addRow('状态:', self.status_combo)
        
        self.priority_combo = QComboBox()
        self.priority_combo.addItems(['低', '中', '高'])
        form_layout.addRow('优先级:', self.priority_combo)
        
        self.content_edit = QTextEdit()
        self.content_edit.setMaximumHeight(100)
        form_layout.addRow('内容:', self.content_edit)
        
        self.acceptance_edit = QLineEdit()
        form_layout.addRow('验收标准:', self.acceptance_edit)
        
        layout.addWidget(form_group)
        
        source_group = QGroupBox('来源信息')
        source_layout = QFormLayout(source_group)
        
        source_type_label = QLabel(self._get_source_display())
        source_layout.addRow('来源:', source_type_label)
        
        self.original_label = QLabel(self.task.get('original_content', '')[:100])
        self.original_label.setWordWrap(True)
        self.original_label.setStyleSheet('color: #666;')
        source_layout.addRow('原始内容:', self.original_label)
        
        created_label = QLabel(self.task.get('created_at', ''))
        source_layout.addRow('创建时间:', created_label)
        
        layout.addWidget(source_group)
        
        action_layout = QHBoxLayout()
        
        copy_btn = QPushButton('📋 一键复制')
        copy_btn.clicked.connect(self._copy_task)
        action_layout.addWidget(copy_btn)
        
        self.confirm_remind_btn = QPushButton('✅ 确认提醒')
        self.confirm_remind_btn.setStyleSheet('''
            QPushButton {
                background-color: #FF9800;
                color: white;
                border: none;
                padding: 6px 16px;
                border-radius: 4px;
                font-weight: bold;
            }
            QPushButton:hover {
                background-color: #F57C00;
            }
        ''')
        self.confirm_remind_btn.clicked.connect(self._confirm_reminder)
        self.confirm_remind_btn.hide()
        action_layout.addWidget(self.confirm_remind_btn)
        
        action_layout.addStretch()
        
        layout.addLayout(action_layout)
        
        button_layout = QHBoxLayout()
        button_layout.addStretch()
        
        cancel_btn = QPushButton('取消')
        cancel_btn.clicked.connect(self.reject)
        button_layout.addWidget(cancel_btn)
        
        save_btn = QPushButton('保存')
        save_btn.clicked.connect(self._save_task)
        save_btn.setDefault(True)
        button_layout.addWidget(save_btn)
        
        layout.addLayout(button_layout)
    
    def _load_task(self):
        self.title_edit.setText(self.task['title'])
        self.owner_edit.setText(self.task.get('owner_name', '我'))
        
        if self.task.get('deadline'):
            deadline_str = self.task['deadline']
            try:
                if len(deadline_str) == 16:
                    dt = datetime.strptime(deadline_str, '%Y-%m-%d %H:%M')
                else:
                    dt = datetime.strptime(deadline_str, '%Y-%m-%d %H:%M:%S')
                self.deadline_edit.setDateTime(QDateTime(dt))
            except:
                pass
        
        status_map = {'pending': 0, 'in_progress': 1, 'completed': 2, 'cancelled': 3}
        self.status_combo.setCurrentIndex(status_map.get(self.task.get('status', 'pending'), 0))
        
        priority_map = {'low': 0, 'medium': 1, 'high': 2}
        self.priority_combo.setCurrentIndex(priority_map.get(self.task.get('priority', 'medium'), 1))
        
        self.content_edit.setText(self.task.get('content', ''))
        self.acceptance_edit.setText(self.task.get('acceptance_criteria', ''))
        
        self._update_status_display()
        self._check_reminder_status()
    
    def _check_reminder_status(self):
        main_window = self.parent()
        if main_window and hasattr(main_window, 'reminding_tasks'):
            if self.task_id in main_window.reminding_tasks:
                self.confirm_remind_btn.show()
    
    def _confirm_reminder(self):
        main_window = self.parent()
        if main_window and hasattr(main_window, 'confirm_reminder'):
            main_window.confirm_reminder(self.task_id)
            self.confirm_remind_btn.hide()
            QMessageBox.information(self, '提示', '已确认提醒，该任务将不再提醒')
    
    def _update_status_display(self):
        status = self.task.get('status', 'pending')
        
        status_styles = {
            'pending': ('待处理', '#9E9E9E'),
            'in_progress': ('进行中', '#2196F3'),
            'completed': ('已完成', '#4CAF50'),
            'cancelled': ('已取消', '#F44336')
        }
        
        text, color = status_styles.get(status, ('未知', '#9E9E9E'))
        self.status_label.setText(text)
        self.status_label.setStyleSheet(f'''
            QLabel {{
                padding: 4px 12px;
                border-radius: 4px;
                font-weight: bold;
                background-color: {color}33;
                color: {color};
            }}
        ''')
        
        priority = self.task.get('priority', 'medium')
        priority_styles = {
            'high': ('高', '#F44336'),
            'medium': ('中', '#FF9800'),
            'low': ('低', '#4CAF50')
        }
        
        p_text, p_color = priority_styles.get(priority, ('中', '#FF9800'))
        self.priority_label.setText(f'优先级: {p_text}')
        self.priority_label.setStyleSheet(f'''
            QLabel {{
                padding: 4px 12px;
                border-radius: 4px;
                background-color: {p_color}33;
                color: {p_color};
            }}
        ''')
    
    def _get_source_display(self) -> str:
        source_type = self.task.get('source_type', 'manual')
        source_map = {
            'manual': '手动输入',
            'clipboard': '剪贴板检测',
            'voice': '语音输入',
            'template': '模板创建'
        }
        return source_map.get(source_type, '未知')
    
    def _copy_task(self):
        text = self.recognition.format_task_for_copy(self.task)
        
        from PyQt5.QtWidgets import QApplication
        QApplication.clipboard().setText(text)
        
        QMessageBox.information(self, '提示', '任务已复制到剪贴板')
    
    def _save_task(self):
        title = self.title_edit.text().strip()
        if not title:
            QMessageBox.warning(self, '提示', '请输入任务标题')
            return
        
        status_map = {0: 'pending', 1: 'in_progress', 2: 'completed', 3: 'cancelled'}
        priority_map = {0: 'low', 1: 'medium', 2: 'high'}
        
        updates = {
            'title': title,
            'owner_name': self.owner_edit.text().strip() or '我',
            'deadline': self.deadline_edit.dateTime().toString('yyyy-MM-dd HH:mm:ss'),
            'status': status_map[self.status_combo.currentIndex()],
            'priority': priority_map[self.priority_combo.currentIndex()],
            'content': self.content_edit.toPlainText().strip(),
            'acceptance_criteria': self.acceptance_edit.text().strip()
        }
        
        if updates['status'] == 'completed' and self.task.get('status') != 'completed':
            updates['completed_at'] = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        
        self.db.update_task(self.task_id, updates)
        self.accept()
