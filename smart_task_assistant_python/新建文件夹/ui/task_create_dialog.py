"""
任务创建对话框 - 带AI识别和优先级分类
"""

import uuid
from datetime import datetime, timedelta
from PyQt5.QtWidgets import (
    QDialog, QVBoxLayout, QHBoxLayout, QLabel, QLineEdit,
    QTextEdit, QPushButton, QComboBox, QDateTimeEdit,
    QFormLayout, QGroupBox, QMessageBox, QProgressBar, QFrame
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
        self.setWindowTitle('创建任务')
        self.setMinimumSize(520, 580)
        
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
        
        self.ai_status_label = QLabel('')
        btn_layout.addWidget(self.ai_status_label)
        
        btn_layout.addStretch()
        content_layout.addLayout(btn_layout)
        
        layout.addWidget(content_group)
        
        self.result_group = QGroupBox('🤖 识别结果')
        result_layout = QVBoxLayout(self.result_group)
        
        self.result_frame = QFrame()
        self.result_frame.setStyleSheet('''
            QFrame {
                background-color: #E3F2FD;
                border-radius: 8px;
                padding: 8px;
            }
        ''')
        result_inner = QVBoxLayout(self.result_frame)
        
        self.confidence_label = QLabel('置信度: --')
        self.confidence_label.setStyleSheet('font-weight: bold;')
        result_inner.addWidget(self.confidence_label)
        
        self.ai_type_label = QLabel('识别方式: --')
        result_inner.addWidget(self.ai_type_label)
        
        result_layout.addWidget(self.result_frame)
        layout.addWidget(self.result_group)
        
        form_group = QGroupBox('📋 任务详情')
        form_layout = QFormLayout(form_group)
        form_layout.setSpacing(10)
        
        self.title_edit = QLineEdit()
        self.title_edit.setPlaceholderText('任务标题')
        form_layout.addRow('标题:', self.title_edit)
        
        self.owner_edit = QLineEdit()
        self.owner_edit.setPlaceholderText('负责人（默认为当前用户）')
        form_layout.addRow('负责人:', self.owner_edit)
        
        self.deadline_edit = QDateTimeEdit()
        self.deadline_edit.setCalendarPopup(True)
        self.deadline_edit.setDateTime(QDateTime.currentDateTime().addSecs(6 * 3600))
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
        form_layout.addRow('验收标准:', self.acceptance_edit)
        
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
            'openai': 'OpenAI GPT',
            'qwen': '通义千问',
            'zhipu': '智谱AI'
        }
        self.ai_type_label.setText(f"识别方式: {api_type_names.get(api_type, '本地规则')}")
        
        if confidence >= 0.7:
            self.result_frame.setStyleSheet('''
                QFrame {
                    background-color: #E8F5E9;
                    border-radius: 8px;
                    padding: 8px;
                }
            ''')
        elif confidence >= 0.4:
            self.result_frame.setStyleSheet('''
                QFrame {
                    background-color: #FFF3E0;
                    border-radius: 8px;
                    padding: 8px;
                }
            ''')
        else:
            self.result_frame.setStyleSheet('''
                QFrame {
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
            'updated_at': now
        }
        
        self.db.insert_task(task)
        self.accept()
