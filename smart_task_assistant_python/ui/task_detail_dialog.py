"""
任务详情对话框
"""

from datetime import datetime, timedelta
from PyQt5.QtWidgets import (
    QDialog, QVBoxLayout, QHBoxLayout, QLabel, QLineEdit,
    QTextEdit, QPushButton, QComboBox, QDateTimeEdit,
    QFormLayout, QGroupBox, QMessageBox, QFrame, QCheckBox, QWidget
)
from PyQt5.QtCore import Qt, QDateTime
import uuid

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
        self.setStyleSheet('''
            QDialog {
                background-color: white;
            }
            QLabel {
                color: #333;
            }
            QGroupBox {
                font-weight: bold;
                border: 1px solid #ddd;
                border-radius: 8px;
                margin-top: 12px;
                padding-top: 12px;
            }
            QGroupBox::title {
                subcontrol-origin: margin;
                left: 12px;
                padding: 0 8px;
            }
            QLineEdit {
                padding: 8px 12px;
                border: 1px solid #ddd;
                border-radius: 6px;
                background-color: white;
            }
            QLineEdit:focus {
                border-color: #2196F3;
            }
            QTextEdit {
                border: 1px solid #ddd;
                border-radius: 6px;
                background-color: white;
            }
            QTextEdit:focus {
                border-color: #2196F3;
            }
            QComboBox {
                padding: 6px 12px;
                border: 1px solid #ddd;
                border-radius: 6px;
                background-color: white;
            }
            QComboBox:focus {
                border-color: #2196F3;
            }
            QComboBox QAbstractItemView {
                background-color: white;
                color: #333;
                selection-background-color: #E3F2FD;
                selection-color: #333;
            }
            QComboBox QAbstractItemView::item {
                color: #333;
                padding: 4px 8px;
            }
            QDateTimeEdit {
                padding: 6px 12px;
                border: 1px solid #ddd;
                border-radius: 6px;
                background-color: white;
            }
            QDateTimeEdit:focus {
                border-color: #2196F3;
            }
            QCheckBox {
                spacing: 6px;
            }
        ''')
        
        self.setWindowTitle('任务详情')
        self.setMinimumSize(700, 600)
        
        main_layout = QHBoxLayout(self)
        main_layout.setSpacing(12)
        
        left_widget = QWidget()
        left_layout = QVBoxLayout(left_widget)
        left_layout.setContentsMargins(0, 0, 0, 0)
        left_layout.setSpacing(10)
        
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
        
        left_layout.addLayout(header_layout)
        
        form_group = QGroupBox('任务信息')
        form_layout = QFormLayout(form_group)
        form_layout.setSpacing(8)
        
        self.title_edit = QLineEdit()
        self.title_edit.setMinimumHeight(32)
        form_layout.addRow('标题:', self.title_edit)
        
        self.owner_edit = QLineEdit()
        self.owner_edit.setMinimumHeight(32)
        form_layout.addRow('负责人:', self.owner_edit)
        
        self.deadline_edit = QDateTimeEdit()
        self.deadline_edit.setCalendarPopup(True)
        self.deadline_edit.setDisplayFormat('yyyy-MM-dd HH:mm')
        self.deadline_edit.setMinimumHeight(32)
        form_layout.addRow('截止时间:', self.deadline_edit)
        
        self.status_combo = QComboBox()
        self.status_combo.addItems(['待处理', '进行中', '已完成', '已取消'])
        form_layout.addRow('状态:', self.status_combo)
        
        self.priority_combo = QComboBox()
        self.priority_combo.addItems(['低', '中', '高'])
        form_layout.addRow('优先级:', self.priority_combo)
        
        self.content_edit = QTextEdit()
        self.content_edit.setMinimumHeight(100)
        self.content_edit.setPlaceholderText('输入任务详细内容...')
        form_layout.addRow('内容:', self.content_edit)
        
        self.acceptance_edit = QLineEdit()
        self.acceptance_edit.setMinimumHeight(32)
        form_layout.addRow('验收标准:', self.acceptance_edit)
        
        left_layout.addWidget(form_group)
        
        tags_group = QGroupBox('标签')
        tags_layout = QVBoxLayout(tags_group)
        tags_layout.setSpacing(4)
        
        self.tags_container = QFrame()
        self.tags_layout_inner = QHBoxLayout(self.tags_container)
        self.tags_layout_inner.setContentsMargins(0, 0, 0, 0)
        self.tags_layout_inner.setSpacing(8)
        
        self.tag_checkboxes = []
        self._load_tags_editable()
        
        tags_layout.addWidget(self.tags_container)
        
        left_layout.addWidget(tags_group)
        
        left_layout.addStretch()
        
        main_layout.addWidget(left_widget, 3)
        
        right_widget = QWidget()
        right_widget.setMaximumWidth(220)
        right_layout = QVBoxLayout(right_widget)
        right_layout.setContentsMargins(0, 0, 0, 0)
        right_layout.setSpacing(10)
        
        header_spacer = QWidget()
        header_spacer.setFixedHeight(28)
        right_layout.addWidget(header_spacer)
        
        reminder_group = QGroupBox('提醒设置')
        reminder_layout = QVBoxLayout(reminder_group)
        reminder_layout.setSpacing(6)
        
        self.reminder_30_check = QCheckBox('30分钟')
        self.reminder_1h_check = QCheckBox('1小时')
        self.reminder_1d_check = QCheckBox('1天')
        self.reminder_3d_check = QCheckBox('3天')
        
        reminder_layout.addWidget(self.reminder_30_check)
        reminder_layout.addWidget(self.reminder_1h_check)
        reminder_layout.addWidget(self.reminder_1d_check)
        reminder_layout.addWidget(self.reminder_3d_check)
        
        right_layout.addWidget(reminder_group)
        
        recurring_group = QGroupBox('重复任务')
        recurring_layout = QVBoxLayout(recurring_group)
        recurring_layout.setSpacing(6)
        
        self.recurring_check = QCheckBox('启用重复')
        self.recurring_check.stateChanged.connect(self._on_recurring_changed)
        recurring_layout.addWidget(self.recurring_check)
        
        self.recurring_combo = QComboBox()
        self.recurring_combo.addItems(['每日', '每周', '每月'])
        self.recurring_combo.setEnabled(False)
        recurring_layout.addWidget(self.recurring_combo)
        
        right_layout.addWidget(recurring_group)
        
        source_group = QGroupBox('📋 来源信息')
        source_layout = QFormLayout(source_group)
        source_layout.setSpacing(8)
        
        source_type_label = QLabel(self._get_source_display())
        source_layout.addRow('来源:', source_type_label)
        
        self.original_label = QLabel(self.task.get('original_content', '')[:100])
        self.original_label.setWordWrap(True)
        self.original_label.setStyleSheet('color: #666;')
        source_layout.addRow('原始内容:', self.original_label)
        
        created_label = QLabel(self.task.get('created_at', ''))
        source_layout.addRow('创建时间:', created_label)
        
        right_layout.addWidget(source_group)
        
        right_layout.addStretch()
        
        main_layout.addWidget(right_widget, 1)
        
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
        
        left_layout.addLayout(action_layout)
        
        button_layout = QHBoxLayout()
        button_layout.addStretch()
        
        cancel_btn = QPushButton('取消')
        cancel_btn.clicked.connect(self.reject)
        button_layout.addWidget(cancel_btn)
        
        save_btn = QPushButton('保存')
        save_btn.clicked.connect(self._save_task)
        save_btn.setDefault(True)
        button_layout.addWidget(save_btn)
        
        left_layout.addLayout(button_layout)
    
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
        
        reminder_times = self.task.get('reminder_times', '')
        if reminder_times:
            times = [t.strip() for t in reminder_times.split(',') if t.strip()]
            if '30' in times:
                self.reminder_30_check.setChecked(True)
            if '60' in times:
                self.reminder_1h_check.setChecked(True)
            if '1440' in times:
                self.reminder_1d_check.setChecked(True)
            if '4320' in times:
                self.reminder_3d_check.setChecked(True)
        
        is_recurring = self.task.get('is_recurring', 0)
        self.recurring_check.setChecked(bool(is_recurring))
        recurring_rule = self.task.get('recurring_rule', '')
        if recurring_rule:
            rule_map = {'daily': 0, 'weekly': 1, 'monthly': 2}
            self.recurring_combo.setCurrentIndex(rule_map.get(recurring_rule, 0))
        
        self._update_status_display()
        self._check_reminder_status()
    
    def _on_recurring_changed(self, state):
        self.recurring_combo.setEnabled(state == Qt.Checked)
    
    def _load_tags_editable(self):
        all_tags = self.db.get_all_tags()
        task_tags = self.db.get_task_tags(self.task_id)
        task_tag_ids = [t['tag_id'] for t in task_tags]
        
        if all_tags:
            for tag in all_tags:
                checkbox = QCheckBox(tag['name'])
                color = tag.get('color', '#2196F3')
                checkbox.setStyleSheet(f'''
                    QCheckBox {{
                        color: {color};
                        font-weight: bold;
                    }}
                ''')
                checkbox.setChecked(tag['tag_id'] in task_tag_ids)
                checkbox.tag_id = tag['tag_id']
                self.tag_checkboxes.append(checkbox)
                self.tags_layout_inner.addWidget(checkbox)
        else:
            no_tags_label = QLabel('暂无标签，请在标签管理中创建')
            no_tags_label.setStyleSheet('color: #999; font-style: italic;')
            self.tags_layout_inner.addWidget(no_tags_label)
    
    def _load_tags(self):
        task_tags = self.db.get_task_tags(self.task_id)
        
        if task_tags:
            for tag in task_tags:
                color = tag.get('color', '#2196F3')
                tag_label = QLabel(f"🏷️ {tag['name']}")
                tag_label.setStyleSheet(f'''
                    QLabel {{
                        color: {color};
                        font-weight: bold;
                        padding: 4px 12px;
                        background-color: {color}22;
                        border-radius: 4px;
                    }}
                ''')
                self.tags_layout_inner.addWidget(tag_label)
        else:
            no_tag_label = QLabel('暂无标签')
            no_tag_label.setStyleSheet('color: #999; font-style: italic;')
            self.tags_layout_inner.addWidget(no_tag_label)
    
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
        try:
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
            
            reminder_times = []
            if self.reminder_30_check.isChecked():
                reminder_times.append('30')
            if self.reminder_1h_check.isChecked():
                reminder_times.append('60')
            if self.reminder_1d_check.isChecked():
                reminder_times.append('1440')
            if self.reminder_3d_check.isChecked():
                reminder_times.append('4320')
            updates['reminder_times'] = ','.join(reminder_times)
            
            updates['is_recurring'] = 1 if self.recurring_check.isChecked() else 0
            if self.recurring_check.isChecked():
                rule_map = {0: 'daily', 1: 'weekly', 2: 'monthly'}
                updates['recurring_rule'] = rule_map[self.recurring_combo.currentIndex()]
            
            self.db.update_task(self.task_id, updates)
            
            for checkbox in self.tag_checkboxes:
                if checkbox.isChecked():
                    self.db.add_task_tag(self.task_id, checkbox.tag_id)
                else:
                    self.db.remove_task_tag(self.task_id, checkbox.tag_id)
            
            should_create_recurring = (updates['status'] == 'completed' and 
                                       self.task.get('status') != 'completed' and 
                                       self.task.get('is_recurring'))
            
            self.accept()
            
            if should_create_recurring:
                self._create_next_recurring_task()
                
        except Exception as e:
            QMessageBox.critical(self, '错误', f'保存失败: {str(e)}')
    
    def _create_next_recurring_task(self):
        rule = self.task.get('recurring_rule', '')
        if not rule:
            return
        
        original_deadline = self.task.get('deadline', '')
        if not original_deadline:
            return
        
        try:
            if len(original_deadline) == 16:
                dt = datetime.strptime(original_deadline, '%Y-%m-%d %H:%M')
            else:
                dt = datetime.strptime(original_deadline, '%Y-%m-%d %H:%M:%S')
            
            if rule == 'daily':
                next_dt = dt + timedelta(days=1)
            elif rule == 'weekly':
                next_dt = dt + timedelta(weeks=1)
            elif rule == 'monthly':
                month = dt.month + 1
                year = dt.year
                if month > 12:
                    month = 1
                    year += 1
                day = min(dt.day, 28)
                next_dt = dt.replace(year=year, month=month, day=day)
            else:
                return
            
            new_task_id = f"T{uuid.uuid4().hex[:8].upper()}"
            now = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            
            new_task = {
                'task_id': new_task_id,
                'title': self.task.get('title', ''),
                'content': self.task.get('content', ''),
                'owner_name': self.task.get('owner_name', '我'),
                'deadline': next_dt.strftime('%Y-%m-%d %H:%M:%S'),
                'status': 'pending',
                'priority': self.task.get('priority', 'medium'),
                'acceptance_criteria': self.task.get('acceptance_criteria', ''),
                'source_type': 'recurring',
                'original_content': self.task.get('original_content', ''),
                'created_at': now,
                'updated_at': now,
                'is_recurring': 1,
                'recurring_rule': rule,
                'parent_task_id': self.task_id,
                'reminder_times': self.task.get('reminder_times', '')
            }
            
            self.db.insert_task(new_task)
            
            task_tags = self.db.get_task_tags(self.task_id)
            for tag in task_tags:
                self.db.add_task_tag(new_task_id, tag['tag_id'])
            
            QMessageBox.information(
                self, '重复任务', 
                f'已自动创建下一个{rule == "daily" and "日" or rule == "weekly" and "周" or "月"}的任务\n截止时间: {next_dt.strftime("%Y-%m-%d %H:%M")}'
            )
            
        except Exception as e:
            print(f"创建重复任务失败: {e}")
