"""
任务创建对话框 - 带AI识别和优先级分类
"""

import uuid
from datetime import datetime, timedelta
from PyQt5.QtWidgets import (
    QDialog, QVBoxLayout, QHBoxLayout, QLabel, QLineEdit,
    QTextEdit, QPushButton, QComboBox, QDateTimeEdit,
    QFormLayout, QGroupBox, QMessageBox, QProgressBar, QFrame,
    QScrollArea, QWidget, QCheckBox
)
from PyQt5.QtCore import Qt, QDateTime, QThread, pyqtSignal

from core.database import DatabaseManager
from core.recognition import TaskRecognitionService


class RecognitionThread(QThread):
    finished = pyqtSignal(dict)
    
    def __init__(self, recognition: TaskRecognitionService, text: str):
        super().__init__()
        self.recognition = recognition
        self.text = text
    
    def run(self):
        result = self.recognition.recognize(self.text)
        self.finished.emit(result)


class TaskCreateDialog(QDialog):
    def __init__(self, parent, db: DatabaseManager, recognition: TaskRecognitionService, initial_content: str = '', source_type: str = 'manual'):
        super().__init__(parent)
        
        self.db = db
        self.recognition = recognition
        self.initial_content = initial_content
        self.source_type = source_type
        self.recognition_thread = None
        
        self._init_ui()
        
        if initial_content:
            self.content_edit.setText(initial_content)
    
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
            QCheckBox {
                spacing: 6px;
            }
        ''')
        
        self.setWindowTitle('创建任务')
        self.setMinimumSize(550, 700)
        
        layout = QVBoxLayout(self)
        layout.setSpacing(12)
        
        content_group = QGroupBox('📝 任务内容')
        content_layout = QVBoxLayout(content_group)
        
        self.content_edit = QTextEdit()
        self.content_edit.setPlaceholderText('输入任务内容，例如：张三，明天下午3点前把周报发给我')
        self.content_edit.setMaximumHeight(100)
        content_layout.addWidget(self.content_edit)
        
        btn_layout = QHBoxLayout()
        
        self.recognize_btn = QPushButton('🔍 智能识别')
        self.recognize_btn.setMinimumHeight(36)
        self.recognize_btn.setStyleSheet('''
            QPushButton {
                background-color: #2196F3;
                color: white;
                border: none;
                border-radius: 6px;
                font-weight: bold;
            }
            QPushButton:hover {
                background-color: #1976D2;
            }
            QPushButton:disabled {
                background-color: #BDBDBD;
            }
        ''')
        self.recognize_btn.clicked.connect(self._on_recognize)
        btn_layout.addWidget(self.recognize_btn)
        
        self.voice_btn = QPushButton('🎤 语音输入')
        self.voice_btn.setMinimumHeight(36)
        self.voice_btn.setStyleSheet('''
            QPushButton {
                background-color: #9C27B0;
                color: white;
                border: none;
                border-radius: 6px;
                font-weight: bold;
            }
            QPushButton:hover {
                background-color: #7B1FA2;
            }
        ''')
        self.voice_btn.clicked.connect(self._on_voice_input)
        btn_layout.addWidget(self.voice_btn)
        
        self.ai_status_label = QLabel('')
        btn_layout.addWidget(self.ai_status_label)
        
        btn_layout.addStretch()
        content_layout.addLayout(btn_layout)
        
        layout.addWidget(content_group)
        
        self.result_group = QGroupBox('🤖 识别结果')
        self.result_group.setMaximumHeight(100)
        result_layout = QHBoxLayout(self.result_group)
        result_layout.setSpacing(20)
        
        self.confidence_label = QLabel('置信度: --')
        self.confidence_label.setStyleSheet('font-weight: bold;')
        result_layout.addWidget(self.confidence_label)
        
        self.ai_type_label = QLabel('识别方式: --')
        result_layout.addWidget(self.ai_type_label)
        
        result_layout.addStretch()
        
        layout.addWidget(self.result_group)
        
        form_group = QGroupBox('📋 任务详情')
        form_layout = QFormLayout(form_group)
        form_layout.setSpacing(10)
        
        self.title_edit = QLineEdit()
        self.title_edit.setPlaceholderText('任务标题')
        self.title_edit.setMinimumHeight(32)
        form_layout.addRow('标题:', self.title_edit)
        
        self.owner_edit = QLineEdit()
        self.owner_edit.setPlaceholderText('负责人（默认为当前用户）')
        self.owner_edit.setMinimumHeight(32)
        form_layout.addRow('负责人:', self.owner_edit)
        
        self.deadline_edit = QDateTimeEdit()
        self.deadline_edit.setCalendarPopup(True)
        self.deadline_edit.setDateTime(QDateTime.currentDateTime().addSecs(6 * 3600))
        self.deadline_edit.setMinimumHeight(32)
        form_layout.addRow('截止时间:', self.deadline_edit)
        
        priority_layout = QHBoxLayout()
        
        self.priority_combo = QComboBox()
        self.priority_combo.addItems(['🟢 低优先级', '🟡 中优先级', '🔴 高优先级'])
        self.priority_combo.setCurrentIndex(1)
        priority_layout.addWidget(self.priority_combo)
        
        priority_hint = QLabel('(低=不紧急, 中=正常, 高=紧急重要)')
        priority_hint.setStyleSheet('color: #666; font-size: 11px;')
        priority_layout.addWidget(priority_hint)
        
        form_layout.addRow('优先级:', priority_layout)
        
        self.acceptance_edit = QLineEdit()
        self.acceptance_edit.setPlaceholderText('验收标准')
        self.acceptance_edit.setMinimumHeight(32)
        form_layout.addRow('验收标准:', self.acceptance_edit)
        
        tags_frame = QFrame()
        tags_layout = QHBoxLayout(tags_frame)
        tags_layout.setContentsMargins(0, 0, 0, 0)
        
        self.tags_container = QWidget()
        self.tags_layout_inner = QHBoxLayout(self.tags_container)
        self.tags_layout_inner.setContentsMargins(0, 0, 0, 0)
        self.tags_layout_inner.setSpacing(8)
        
        self.tag_checkboxes = []
        self._load_tags()
        
        tags_layout.addWidget(self.tags_container)
        tags_layout.addStretch()
        
        form_layout.addRow('标签:', tags_frame)
        
        recurring_frame = QFrame()
        recurring_layout = QHBoxLayout(recurring_frame)
        recurring_layout.setContentsMargins(0, 0, 0, 0)
        
        self.recurring_check = QCheckBox('启用重复')
        self.recurring_check.stateChanged.connect(self._on_recurring_changed)
        recurring_layout.addWidget(self.recurring_check)
        
        self.recurring_combo = QComboBox()
        self.recurring_combo.addItems(['每日', '每周', '每月'])
        self.recurring_combo.setEnabled(False)
        self.recurring_combo.setStyleSheet('padding: 4px 8px;')
        recurring_layout.addWidget(self.recurring_combo)
        
        recurring_hint = QLabel('(自动创建后续任务)')
        recurring_hint.setStyleSheet('color: #666; font-size: 11px;')
        recurring_layout.addWidget(recurring_hint)
        
        recurring_layout.addStretch()
        
        form_layout.addRow('重复:', recurring_frame)
        
        reminder_frame = QFrame()
        reminder_layout = QHBoxLayout(reminder_frame)
        reminder_layout.setContentsMargins(0, 0, 0, 0)
        
        reminder_label = QLabel('提前提醒:')
        reminder_layout.addWidget(reminder_label)
        
        self.reminder_30_check = QCheckBox('30分钟')
        self.reminder_30_check.setChecked(True)
        reminder_layout.addWidget(self.reminder_30_check)
        
        self.reminder_1h_check = QCheckBox('1小时')
        self.reminder_1h_check.setChecked(True)
        reminder_layout.addWidget(self.reminder_1h_check)
        
        self.reminder_1d_check = QCheckBox('1天')
        reminder_layout.addWidget(self.reminder_1d_check)
        
        self.reminder_3d_check = QCheckBox('3天')
        reminder_layout.addWidget(self.reminder_3d_check)
        
        reminder_layout.addStretch()
        
        form_layout.addRow('提醒:', reminder_frame)
        
        layout.addWidget(form_group)
        
        button_layout = QHBoxLayout()
        button_layout.addStretch()
        
        cancel_btn = QPushButton('取消')
        cancel_btn.setMinimumWidth(80)
        cancel_btn.clicked.connect(self.reject)
        button_layout.addWidget(cancel_btn)
        
        save_btn = QPushButton('💾 保存任务')
        save_btn.setMinimumWidth(100)
        save_btn.setStyleSheet('''
            QPushButton {
                background-color: #4CAF50;
                color: white;
                border: none;
                border-radius: 6px;
                font-weight: bold;
            }
            QPushButton:hover {
                background-color: #388E3C;
            }
        ''')
        save_btn.clicked.connect(self._save_task)
        save_btn.setDefault(True)
        button_layout.addWidget(save_btn)
        
        layout.addLayout(button_layout)
    
    def _on_recognize(self):
        content = self.content_edit.toPlainText().strip()
        if not content:
            QMessageBox.warning(self, '提示', '请输入任务内容')
            return
        
        self.recognize_btn.setEnabled(False)
        self.recognize_btn.setText('⏳ 识别中...')
        self.ai_status_label.setText('正在调用AI服务...')
        
        self.recognition_thread = RecognitionThread(self.recognition, content)
        self.recognition_thread.finished.connect(self._on_recognition_finished)
        self.recognition_thread.start()
    
    def _on_recognition_finished(self, result: dict):
        self.recognize_btn.setEnabled(True)
        self.recognize_btn.setText('🔍 智能识别')
        
        confidence = result.get('confidence', 0)
        self.confidence_label.setText(f"置信度: {confidence * 100:.0f}%")
        
        api_type = self.recognition.ai_service.api_type
        api_type_names = {
            'local': '本地规则',
            'doubao': '豆包',
            'qwen': '通义千问',
            'zhipu': '智谱AI',
            'kimi': 'Kimi'
        }
        self.ai_type_label.setText(f"识别方式: {api_type_names.get(api_type, '本地规则')}")
        
        if confidence >= 0.7:
            self.result_group.setStyleSheet('''
                QGroupBox {
                    background-color: #E8F5E9;
                    border-radius: 8px;
                    padding: 8px;
                }
            ''')
        elif confidence >= 0.4:
            self.result_group.setStyleSheet('''
                QGroupBox {
                    background-color: #FFF3E0;
                    border-radius: 8px;
                    padding: 8px;
                }
            ''')
        else:
            self.result_group.setStyleSheet('''
                QGroupBox {
                    background-color: #FFEBEE;
                    border-radius: 8px;
                    padding: 8px;
                }
            ''')
        
        if result['title']:
            self.title_edit.setText(result['title'])
        
        if result.get('owner_name'):
            self.owner_edit.setText(result['owner_name'])
        
        if result['deadline']:
            try:
                dt = datetime.strptime(result['deadline'], '%Y-%m-%d %H:%M:%S')
                self.deadline_edit.setDateTime(QDateTime(dt))
            except:
                pass
        
        priority_map = {'low': 0, 'medium': 1, 'high': 2}
        self.priority_combo.setCurrentIndex(priority_map.get(result.get('priority', 'medium'), 1))
        
        if result.get('acceptance_criteria'):
            self.acceptance_edit.setText(result['acceptance_criteria'])
        
        self.ai_status_label.setText(f'✅ 识别完成')
    
    def _load_tags(self):
        tags = self.db.get_all_tags()
        
        for tag in tags:
            checkbox = QCheckBox(tag['name'])
            color = tag.get('color', '#2196F3')
            checkbox.setStyleSheet(f'''
                QCheckBox {{
                    color: {color};
                    font-weight: bold;
                    padding: 4px 8px;
                }}
                QCheckBox::indicator {{
                    width: 16px;
                    height: 16px;
                }}
            ''')
            checkbox.tag_id = tag['tag_id']
            self.tag_checkboxes.append(checkbox)
            self.tags_layout_inner.addWidget(checkbox)
        
        if not tags:
            no_tags_label = QLabel('暂无标签，请先在"标签管理"中创建')
            no_tags_label.setStyleSheet('color: #999; font-style: italic;')
            self.tags_layout_inner.addWidget(no_tags_label)
    
    def _on_recurring_changed(self, state):
        self.recurring_combo.setEnabled(state == Qt.Checked)
    
    def _on_voice_input(self):
        from core.voice_input import VoiceInputService
        
        voice_service = VoiceInputService()
        
        if not voice_service.is_available:
            reply = QMessageBox.question(
                self, '语音输入不可用',
                f'语音输入功能需要安装额外依赖：\n\n{voice_service.install_instructions()}\n\n是否查看安装说明？',
                QMessageBox.Yes | QMessageBox.No
            )
            if reply == QMessageBox.Yes:
                QMessageBox.information(self, '安装说明', voice_service.install_instructions())
            return
        
        self.voice_btn.setText('🎤 正在录音...')
        self.voice_btn.setEnabled(False)
        self.ai_status_label.setText('🎤 请说话...')
        
        from PyQt5.QtCore import QTimer
        QTimer.singleShot(100, lambda: self._do_voice_input(voice_service))
    
    def _do_voice_input(self, voice_service):
        text = voice_service.listen(timeout=5)
        
        self.voice_btn.setText('🎤 语音输入')
        self.voice_btn.setEnabled(True)
        
        if text:
            self.content_edit.setPlainText(text)
            self.ai_status_label.setText(f'✅ 语音识别成功')
            self._on_recognize()
        else:
            self.ai_status_label.setText('❌ 语音识别失败，请重试')
            QMessageBox.warning(self, '提示', '语音识别失败，请确保麦克风正常工作并重试')
    
    def _save_task(self):
        title = self.title_edit.text().strip()
        if not title:
            QMessageBox.warning(self, '提示', '请输入任务标题')
            return
        
        task_id = f"T{uuid.uuid4().hex[:8].upper()}"
        now = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        
        priority_map = {0: 'low', 1: 'medium', 2: 'high'}
        
        task = {
            'task_id': task_id,
            'title': title,
            'content': self.content_edit.toPlainText().strip(),
            'owner_name': self.owner_edit.text().strip() or '我',
            'deadline': self.deadline_edit.dateTime().toString('yyyy-MM-dd HH:mm:ss'),
            'status': 'pending',
            'priority': priority_map[self.priority_combo.currentIndex()],
            'acceptance_criteria': self.acceptance_edit.text().strip(),
            'source_type': self.source_type,
            'original_content': self.content_edit.toPlainText().strip(),
            'created_at': now,
            'updated_at': now,
            'is_recurring': 1 if self.recurring_check.isChecked() else 0,
            'recurring_rule': self._get_recurring_rule() if self.recurring_check.isChecked() else '',
            'reminder_times': self._get_reminder_times()
        }
        
        self.db.insert_task(task)
        
        for checkbox in self.tag_checkboxes:
            if checkbox.isChecked():
                self.db.add_task_tag(task_id, checkbox.tag_id)
        
        self.accept()
    
    def _get_recurring_rule(self) -> str:
        rules = ['daily', 'weekly', 'monthly']
        return rules[self.recurring_combo.currentIndex()]
    
    def _get_reminder_times(self) -> str:
        times = []
        if self.reminder_30_check.isChecked():
            times.append('30')
        if self.reminder_1h_check.isChecked():
            times.append('60')
        if self.reminder_1d_check.isChecked():
            times.append('1440')
        if self.reminder_3d_check.isChecked():
            times.append('4320')
        return ','.join(times)
