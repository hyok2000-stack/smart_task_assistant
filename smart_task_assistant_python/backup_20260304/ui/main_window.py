"""
主窗口界面 - 日常工具风格设计
"""

import uuid
from datetime import datetime, timedelta
from PyQt5.QtWidgets import (
    QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QLabel, QPushButton, QListWidget, QListWidgetItem,
    QFrame, QMessageBox, QInputDialog, QMenu, QAction,
    QComboBox, QLineEdit, QGridLayout, QDialog, QTextEdit, QApplication,
    QSystemTrayIcon
)
from PyQt5.QtCore import Qt, QTimer, pyqtSignal
from PyQt5.QtGui import QFont, QIcon, QPixmap, QColor

from core.database import DatabaseManager
from core.config import Config
from core.recognition import TaskRecognitionService
from core.clipboard import ClipboardService
from ui.task_create_dialog import TaskCreateDialog
from ui.task_detail_dialog import TaskDetailDialog
from ui.settings_dialog import SettingsDialog
from ui.widgets.stats_card import StatsCard
from ui.widgets.task_card import TaskCardWidget


class MainWindow(QMainWindow):
    def __init__(self, db: DatabaseManager, config: Config):
        super().__init__()
        
        self.db = db
        self.config = config
        self.recognition = TaskRecognitionService(
            api_type=config.get('ai_type', 'local'),
            api_key=config.get('ai_api_key', ''),
            api_base=config.get('ai_api_base', '')
        )
        self.clipboard = ClipboardService()
        
        self.current_status_filter = 'all'
        self.filter_priority = ''
        self.filter_owner = ''
        self.filter_time = ''
        self.filter_title = ''
        self.filter_content = ''
        
        self.reminding_tasks = set()
        self.confirmed_reminders = set()
        self.is_icon_flashing = False
        self.flash_state = False
        
        self._init_ui()
        self._init_connections()
        self._init_tray()
        self._init_reminder()
        self._load_data()
        
        if self.config.get('auto_detect_clipboard', True):
            self.clipboard.clipboard_detected.connect(self._on_clipboard_detected)
            self.clipboard.start_monitoring()
    
    def _init_ui(self):
        self.setWindowTitle('智能任务助手')
        self.setMinimumSize(900, 600)
        self.resize(1000, 700)
        
        self.setStyleSheet('''
            QMainWindow {
                background-color: #f5f5f5;
            }
            QLabel {
                color: #333;
            }
            QPushButton {
                padding: 8px 16px;
                border-radius: 6px;
                font-size: 13px;
            }
            QPushButton:hover {
                background-color: #e0e0e0;
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
        ''')
        
        central_widget = QWidget()
        self.setCentralWidget(central_widget)
        
        main_layout = QVBoxLayout(central_widget)
        main_layout.setContentsMargins(16, 12, 16, 12)
        main_layout.setSpacing(12)
        
        header_frame = QFrame()
        header_frame.setStyleSheet('''
            QFrame {
                background-color: white;
                border-radius: 8px;
                padding: 8px 12px;
            }
        ''')
        header_layout = QHBoxLayout(header_frame)
        header_layout.setSpacing(12)
        
        title_label = QLabel('📋 智能任务助手')
        title_label.setFont(QFont('Microsoft YaHei', 14, QFont.Bold))
        title_label.setStyleSheet('color: #1976D2;')
        header_layout.addWidget(title_label)
        
        self.date_label = QLabel(datetime.now().strftime('%Y-%m-%d'))
        self.date_label.setStyleSheet('color: #999; font-size: 11px;')
        header_layout.addWidget(self.date_label)
        
        header_layout.addStretch()
        
        self.chat_btn = QPushButton('💬 智答')
        self.chat_btn.setFixedWidth(70)
        self.chat_btn.setStyleSheet('''
            QPushButton {
                background-color: #2196F3;
                color: white;
                border: none;
                padding: 4px 8px;
                border-radius: 4px;
            }
            QPushButton:hover {
                background-color: #1976D2;
            }
        ''')
        self.chat_btn.clicked.connect(self._show_chat_dialog)
        header_layout.addWidget(self.chat_btn)
        
        self.clipboard_btn = QPushButton('📋 监听')
        self.clipboard_btn.setCheckable(True)
        self.clipboard_btn.setChecked(True)
        self.clipboard_btn.setFixedWidth(70)
        self.clipboard_btn.setStyleSheet('padding: 4px 8px;')
        header_layout.addWidget(self.clipboard_btn)
        
        self.settings_btn = QPushButton('⚙ 设置')
        self.settings_btn.setFixedWidth(70)
        self.settings_btn.setStyleSheet('padding: 4px 8px;')
        header_layout.addWidget(self.settings_btn)
        
        self.about_btn = QPushButton('ℹ 关于')
        self.about_btn.setFixedWidth(70)
        self.about_btn.setStyleSheet('padding: 4px 8px;')
        self.about_btn.clicked.connect(self._show_about)
        header_layout.addWidget(self.about_btn)
        
        main_layout.addWidget(header_frame)
        
        stats_frame = QFrame()
        stats_frame.setStyleSheet('''
            QFrame {
                background-color: transparent;
            }
        ''')
        stats_layout = QHBoxLayout(stats_frame)
        stats_layout.setSpacing(10)
        
        self.all_card = StatsCard('全部', 0, '#9E9E9E', '📋', 'all')
        self.pending_card = StatsCard('待处理', 0, '#FF9800', '⏳', 'pending')
        self.in_progress_card = StatsCard('进行中', 0, '#2196F3', '🔄', 'in_progress')
        self.completed_card = StatsCard('已完成', 0, '#4CAF50', '✅', 'completed')
        self.overdue_card = StatsCard('已逾期', 0, '#F44336', '⚠️', 'overdue')
        
        stats_layout.addWidget(self.all_card)
        stats_layout.addWidget(self.pending_card)
        stats_layout.addWidget(self.in_progress_card)
        stats_layout.addWidget(self.completed_card)
        stats_layout.addWidget(self.overdue_card)
        
        main_layout.addWidget(stats_frame)
        
        filter_frame = QFrame()
        filter_frame.setStyleSheet('''
            QFrame {
                background-color: white;
                border-radius: 8px;
                padding: 10px 12px;
            }
        ''')
        filter_layout = QHBoxLayout(filter_frame)
        filter_layout.setSpacing(12)
        filter_layout.setContentsMargins(12, 8, 12, 8)
        
        priority_label = QLabel('优先级:')
        priority_label.setStyleSheet('font-weight: bold;')
        filter_layout.addWidget(priority_label)
        
        self.priority_combo = QComboBox()
        self.priority_combo.addItem('全部', '')
        self.priority_combo.addItem('🔴 高', 'high')
        self.priority_combo.addItem('🟡 中', 'medium')
        self.priority_combo.addItem('🟢 低', 'low')
        self.priority_combo.setMinimumWidth(80)
        self.priority_combo.setStyleSheet('''
            QComboBox {
                padding: 4px 8px;
                border: 1px solid #ddd;
                border-radius: 4px;
            }
            QComboBox:focus {
                border-color: #2196F3;
            }
        ''')
        filter_layout.addWidget(self.priority_combo)
        
        filter_layout.addSpacing(8)
        
        owner_label = QLabel('负责人:')
        owner_label.setStyleSheet('font-weight: bold;')
        filter_layout.addWidget(owner_label)
        
        self.owner_input = QLineEdit()
        self.owner_input.setPlaceholderText('姓名...')
        self.owner_input.setMaximumWidth(100)
        self.owner_input.setStyleSheet('''
            QLineEdit {
                padding: 4px 8px;
                border: 1px solid #ddd;
                border-radius: 4px;
            }
            QLineEdit:focus {
                border-color: #2196F3;
            }
        ''')
        filter_layout.addWidget(self.owner_input)
        
        filter_layout.addSpacing(8)
        
        time_label = QLabel('时间:')
        time_label.setStyleSheet('font-weight: bold;')
        filter_layout.addWidget(time_label)
        
        self.time_combo = QComboBox()
        self.time_combo.addItem('全部', '')
        self.time_combo.addItem('今天', 'today')
        self.time_combo.addItem('明天', 'tomorrow')
        self.time_combo.addItem('本周', 'this_week')
        self.time_combo.addItem('本月', 'this_month')
        self.time_combo.addItem('已逾期', 'overdue')
        self.time_combo.setMinimumWidth(80)
        self.time_combo.setStyleSheet('''
            QComboBox {
                padding: 4px 8px;
                border: 1px solid #ddd;
                border-radius: 4px;
            }
            QComboBox:focus {
                border-color: #2196F3;
            }
        ''')
        filter_layout.addWidget(self.time_combo)
        
        filter_layout.addSpacing(8)
        
        title_filter_label = QLabel('标题:')
        title_filter_label.setStyleSheet('font-weight: bold;')
        filter_layout.addWidget(title_filter_label)
        
        self.title_input = QLineEdit()
        self.title_input.setPlaceholderText('关键词...')
        self.title_input.setMaximumWidth(120)
        self.title_input.setStyleSheet('''
            QLineEdit {
                padding: 4px 8px;
                border: 1px solid #ddd;
                border-radius: 4px;
            }
            QLineEdit:focus {
                border-color: #2196F3;
            }
        ''')
        filter_layout.addWidget(self.title_input)
        
        filter_layout.addSpacing(8)
        
        content_filter_label = QLabel('内容:')
        content_filter_label.setStyleSheet('font-weight: bold;')
        filter_layout.addWidget(content_filter_label)
        
        self.content_input = QLineEdit()
        self.content_input.setPlaceholderText('关键词...')
        self.content_input.setMaximumWidth(120)
        self.content_input.setStyleSheet('''
            QLineEdit {
                padding: 4px 8px;
                border: 1px solid #ddd;
                border-radius: 4px;
            }
            QLineEdit:focus {
                border-color: #2196F3;
            }
        ''')
        filter_layout.addWidget(self.content_input)
        
        filter_layout.addStretch()
        
        self.clear_filter_btn = QPushButton('清除')
        self.clear_filter_btn.setStyleSheet('''
            QPushButton {
                background-color: #f5f5f5;
                border: 1px solid #ddd;
                padding: 4px 12px;
                border-radius: 4px;
            }
            QPushButton:hover {
                background-color: #e0e0e0;
            }
        ''')
        filter_layout.addWidget(self.clear_filter_btn)
        
        self.apply_filter_btn = QPushButton('🔍 筛选')
        self.apply_filter_btn.setStyleSheet('''
            QPushButton {
                background-color: #2196F3;
                color: white;
                border: none;
                padding: 4px 16px;
                border-radius: 4px;
            }
            QPushButton:hover {
                background-color: #1976D2;
            }
        ''')
        filter_layout.addWidget(self.apply_filter_btn)
        
        main_layout.addWidget(filter_frame)
        
        list_frame = QFrame()
        list_frame.setStyleSheet('''
            QFrame {
                background-color: white;
                border-radius: 12px;
            }
        ''')
        list_layout = QVBoxLayout(list_frame)
        list_layout.setContentsMargins(12, 12, 12, 12)
        
        self.task_list = QListWidget()
        self.task_list.setFrameShape(QFrame.NoFrame)
        self.task_list.setSpacing(6)
        self.task_list.setStyleSheet('''
            QListWidget {
                background-color: transparent;
                border: none;
            }
            QListWidget::item {
                border-radius: 8px;
            }
        ''')
        self.task_list.itemDoubleClicked.connect(self._on_task_double_clicked)
        self.task_list.setContextMenuPolicy(Qt.CustomContextMenu)
        self.task_list.customContextMenuRequested.connect(self._show_context_menu)
        
        list_layout.addWidget(self.task_list)
        
        main_layout.addWidget(list_frame, 1)
        
        bottom_frame = QFrame()
        bottom_frame.setStyleSheet('''
            QFrame {
                background-color: transparent;
            }
        ''')
        bottom_layout = QHBoxLayout(bottom_frame)
        
        self.quick_input = QPushButton('⚡ 快速创建')
        self.quick_input.setMinimumHeight(44)
        self.quick_input.setStyleSheet('''
            QPushButton {
                background-color: white;
                color: #2196F3;
                border: 2px solid #2196F3;
                border-radius: 8px;
                font-size: 14px;
                font-weight: bold;
            }
            QPushButton:hover {
                background-color: #E3F2FD;
            }
        ''')
        bottom_layout.addWidget(self.quick_input)
        
        self.new_task_btn = QPushButton('➕ 新建任务')
        self.new_task_btn.setMinimumHeight(44)
        self.new_task_btn.setStyleSheet('''
            QPushButton {
                background-color: #2196F3;
                color: white;
                border: none;
                border-radius: 8px;
                font-size: 14px;
                font-weight: bold;
            }
            QPushButton:hover {
                background-color: #1976D2;
            }
        ''')
        bottom_layout.addWidget(self.new_task_btn)
        
        main_layout.addWidget(bottom_frame)
        
        self.statusBar().setStyleSheet('''
            QStatusBar {
                background-color: white;
                color: #666;
                font-size: 12px;
            }
        ''')
        self.statusBar().showMessage('就绪 - 双击任务查看详情')
    
    def _init_connections(self):
        self.new_task_btn.clicked.connect(self._create_task)
        self.quick_input.clicked.connect(self._quick_create_task)
        self.clipboard_btn.toggled.connect(self._toggle_clipboard)
        self.settings_btn.clicked.connect(self._show_settings)
        
        self.all_card.clicked.connect(self._on_card_clicked)
        self.pending_card.clicked.connect(self._on_card_clicked)
        self.in_progress_card.clicked.connect(self._on_card_clicked)
        self.completed_card.clicked.connect(self._on_card_clicked)
        self.overdue_card.clicked.connect(self._on_card_clicked)
        
        self.apply_filter_btn.clicked.connect(self._apply_filters)
        self.clear_filter_btn.clicked.connect(self._clear_filters)
        
        self.priority_combo.currentIndexChanged.connect(self._on_filter_changed)
        self.time_combo.currentIndexChanged.connect(self._on_filter_changed)
        
        self.owner_input.textChanged.connect(self._on_filter_changed)
        self.title_input.textChanged.connect(self._on_filter_changed)
    
    def _on_card_clicked(self, filter_key: str):
        self.current_status_filter = filter_key
        self._clear_filter_inputs()
        self._load_tasks()
        
        status_names = {
            'all': '全部',
            'pending': '待处理',
            'in_progress': '进行中',
            'completed': '已完成',
            'overdue': '已逾期'
        }
        self.statusBar().showMessage(f'📋 筛选: {status_names.get(filter_key, "全部")}任务')
    
    def _on_filter_changed(self):
        pass
    
    def _apply_filters(self):
        self.filter_priority = self.priority_combo.currentData() or ''
        self.filter_owner = self.owner_input.text().strip()
        self.filter_time = self.time_combo.currentData() or ''
        self.filter_title = self.title_input.text().strip()
        self.filter_content = self.content_input.text().strip()
        self.current_status_filter = 'all'
        
        self._load_tasks()
        
        filter_desc = []
        if self.filter_priority:
            priority_names = {'high': '高优先级', 'medium': '中优先级', 'low': '低优先级'}
            filter_desc.append(priority_names.get(self.filter_priority, ''))
        if self.filter_owner:
            filter_desc.append(f'负责人:{self.filter_owner}')
        if self.filter_time:
            time_names = {'today': '今天', 'tomorrow': '明天', 'this_week': '本周', 'this_month': '本月', 'overdue': '已逾期'}
            filter_desc.append(time_names.get(self.filter_time, ''))
        if self.filter_title:
            filter_desc.append(f'标题:{self.filter_title}')
        if self.filter_content:
            filter_desc.append(f'内容:{self.filter_content}')
        
        if filter_desc:
            self.statusBar().showMessage(f'🔍 筛选: {", ".join(filter_desc)}')
        else:
            self.statusBar().showMessage('🔍 显示全部任务')
    
    def _clear_filters(self):
        self._clear_filter_inputs()
        self.current_status_filter = 'all'
        self.filter_priority = ''
        self.filter_owner = ''
        self.filter_time = ''
        self.filter_title = ''
        self.filter_content = ''
        self._load_tasks()
        self.statusBar().showMessage('🔍 已清除筛选条件')
    
    def _clear_filter_inputs(self):
        self.priority_combo.setCurrentIndex(0)
        self.time_combo.setCurrentIndex(0)
        self.owner_input.clear()
        self.title_input.clear()
        self.content_input.clear()
        self.filter_priority = ''
        self.filter_owner = ''
        self.filter_time = ''
        self.filter_title = ''
        self.filter_content = ''
    
    def _load_data(self):
        self._update_stats()
        self._load_tasks()
    
    def _update_stats(self):
        stats = self.db.get_task_stats()
        self.all_card.set_count(stats.get('total', 0))
        self.pending_card.set_count(stats.get('pending', 0))
        self.in_progress_card.set_count(stats.get('in_progress', 0))
        self.completed_card.set_count(stats.get('completed', 0))
        self.overdue_card.set_count(stats.get('overdue', 0))
    
    def _load_tasks(self):
        self.task_list.clear()
        
        if self.current_status_filter != 'all':
            if self.current_status_filter == 'overdue':
                tasks = self.db.get_overdue_tasks()
            else:
                tasks = self.db.get_tasks_by_status(self.current_status_filter)
        elif self.filter_priority or self.filter_owner or self.filter_time or self.filter_title or self.filter_content:
            tasks = self.db.get_tasks_by_filters(
                priority=self.filter_priority,
                owner=self.filter_owner,
                time_filter=self.filter_time,
                title=self.filter_title,
                content=self.filter_content
            )
        else:
            tasks = self.db.get_all_tasks()
        
        for task in tasks:
            item = QListWidgetItem()
            card = TaskCardWidget(task)
            item.setSizeHint(card.sizeHint())
            item.setData(Qt.UserRole, task['task_id'])
            self.task_list.addItem(item)
            self.task_list.setItemWidget(item, card)
        
        self.statusBar().showMessage(f'共 {len(tasks)} 条任务')
    
    def _create_task(self):
        dialog = TaskCreateDialog(self, self.db, self.recognition)
        if dialog.exec_():
            self._load_data()
            self.statusBar().showMessage('✅ 任务创建成功')
    
    def _quick_create_task(self):
        dialog = QDialog(self)
        dialog.setWindowTitle('⚡ 快速创建任务')
        dialog.setMinimumSize(450, 200)
        
        layout = QVBoxLayout(dialog)
        layout.setSpacing(12)
        
        label = QLabel('输入任务内容（AI将自动识别标题、时间、优先级等）：')
        label.setStyleSheet('font-weight: bold; color: #333;')
        layout.addWidget(label)
        
        text_edit = QTextEdit()
        text_edit.setPlaceholderText('例如：明天下午3点前完成项目报告，交给张三，比较紧急')
        text_edit.setStyleSheet('''
            QTextEdit {
                border: 1px solid #ddd;
                border-radius: 6px;
                padding: 8px;
                font-size: 14px;
            }
            QTextEdit:focus {
                border-color: #2196F3;
            }
        ''')
        text_edit.setMaximumHeight(100)
        layout.addWidget(text_edit)
        
        btn_layout = QHBoxLayout()
        btn_layout.addStretch()
        
        cancel_btn = QPushButton('取消')
        cancel_btn.clicked.connect(dialog.reject)
        btn_layout.addWidget(cancel_btn)
        
        create_btn = QPushButton('✨ 创建任务')
        create_btn.setStyleSheet('''
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
        create_btn.clicked.connect(dialog.accept)
        btn_layout.addWidget(create_btn)
        
        layout.addLayout(btn_layout)
        
        if dialog.exec_() != QDialog.Accepted:
            return
        
        text = text_edit.toPlainText().strip()
        if not text:
            return
        
        self.statusBar().showMessage('⏳ AI识别中...')
        QApplication.processEvents()
        
        result = self.recognition.recognize(text)
        
        task_id = f"T{uuid.uuid4().hex[:8].upper()}"
        now = datetime.now()
        now_str = now.strftime('%Y-%m-%d %H:%M:%S')
        tomorrow_18 = (now + timedelta(days=1)).replace(hour=18, minute=0, second=0).strftime('%Y-%m-%d %H:%M:%S')
        
        task = {
            'task_id': task_id,
            'title': result.get('title') or text[:50],
            'content': text,
            'owner_name': result.get('owner_name') or '我',
            'deadline': result.get('deadline') or tomorrow_18,
            'status': 'pending',
            'priority': result.get('priority', 'medium'),
            'acceptance_criteria': result.get('acceptance_criteria', ''),
            'source_type': 'quick_create',
            'original_content': text,
            'created_at': now_str,
            'updated_at': now_str
        }
        
        self.db.insert_task(task)
        
        priority_names = {'high': '🔴高', 'medium': '🟡中', 'low': '🟢低'}
        self.statusBar().showMessage(
            f"✅ 已创建: {task['title']} | {priority_names.get(task['priority'], '🟡中')} | {task['deadline'][:10]}"
        )
        
        self._update_stats()
        self._load_tasks()
    
    def _on_task_double_clicked(self, item: QListWidgetItem):
        task_id = item.data(Qt.UserRole)
        self._show_task_detail(task_id)
    
    def _show_task_detail(self, task_id: str):
        dialog = TaskDetailDialog(self, self.db, self.recognition, task_id)
        if dialog.exec_():
            self._load_data()
    
    def _show_context_menu(self, pos):
        item = self.task_list.itemAt(pos)
        if not item:
            return
        
        task_id = item.data(Qt.UserRole)
        task = self.db.get_task_by_id(task_id)
        if not task:
            return
        
        menu = QMenu(self)
        menu.setStyleSheet('''
            QMenu {
                background-color: white;
                border: 1px solid #ddd;
                border-radius: 8px;
                padding: 4px;
            }
            QMenu::item {
                padding: 8px 24px;
                border-radius: 4px;
            }
            QMenu::item:selected {
                background-color: #E3F2FD;
            }
        ''')
        
        copy_action = QAction('📋 一键复制', self)
        copy_action.triggered.connect(lambda: self._copy_task(task_id))
        menu.addAction(copy_action)
        
        menu.addSeparator()
        
        if task['status'] != 'completed':
            complete_action = QAction('✅ 标记完成', self)
            complete_action.triggered.connect(lambda: self._complete_task(task_id))
            menu.addAction(complete_action)
        
        if task['status'] == 'pending':
            start_action = QAction('▶️ 开始处理', self)
            start_action.triggered.connect(lambda: self._start_task(task_id))
            menu.addAction(start_action)
        
        menu.addSeparator()
        
        delete_action = QAction('🗑️ 删除任务', self)
        delete_action.triggered.connect(lambda: self._delete_task(task_id))
        menu.addAction(delete_action)
        
        menu.exec_(self.task_list.mapToGlobal(pos))
    
    def _copy_task(self, task_id: str):
        task = self.db.get_task_by_id(task_id)
        if task:
            text = self.recognition.format_task_for_copy(task)
            self.clipboard.copy_to_clipboard(text)
            self.statusBar().showMessage('📋 已复制到剪贴板')
    
    def _complete_task(self, task_id: str):
        self.db.update_task_status(task_id, 'completed')
        self._load_data()
        self.statusBar().showMessage('✅ 任务已完成')
    
    def _start_task(self, task_id: str):
        self.db.update_task_status(task_id, 'in_progress')
        self._load_data()
        self.statusBar().showMessage('▶️ 任务已开始')
    
    def _delete_task(self, task_id: str):
        reply = QMessageBox.question(
            self, '确认删除', '确定要删除这个任务吗？',
            QMessageBox.Yes | QMessageBox.No, QMessageBox.No
        )
        
        if reply == QMessageBox.Yes:
            self.db.delete_task(task_id)
            self._load_data()
            self.statusBar().showMessage('🗑️ 任务已删除')
    
    def _toggle_clipboard(self, checked: bool):
        if checked:
            self.clipboard.start_monitoring()
            self.statusBar().showMessage('📋 剪贴板监听已开启')
        else:
            self.clipboard.stop_monitoring()
            self.statusBar().showMessage('📋 剪贴板监听已关闭')
    
    def _show_settings(self):
        dialog = SettingsDialog(self, self.config)
        if dialog.exec_():
            self.recognition.configure(
                api_type=self.config.get('ai_type', 'local'),
                api_key=self.config.get('ai_api_key', ''),
                api_base=self.config.get('ai_api_base', '')
            )
            
            auto_clipboard = self.config.get('auto_detect_clipboard', True)
            self.clipboard_btn.setChecked(auto_clipboard)
            if auto_clipboard:
                self.clipboard.start_monitoring()
            else:
                self.clipboard.stop_monitoring()
            
            self.statusBar().showMessage('⚙️ 设置已更新')
    
    def _show_chat_dialog(self):
        from ui.chat_dialog import ChatDialog
        dialog = ChatDialog(self, self.config)
        dialog.exec_()
    
    def _show_about(self):
        from ui.about_dialog import AboutDialog
        dialog = AboutDialog(self)
        dialog.exec_()
    
    def _on_clipboard_detected(self, content: str):
        reply = QMessageBox.question(
            self, '📋 检测到新内容',
            f'检测到剪贴板内容:\n\n{content[:100]}...\n\n是否创建任务？',
            QMessageBox.Yes | QMessageBox.No, QMessageBox.Yes
        )
        
        if reply == QMessageBox.Yes:
            dialog = TaskCreateDialog(self, self.db, self.recognition, content, source_type='clipboard')
            if dialog.exec_():
                self._load_data()
    
    def _init_tray(self):
        self.normal_icon = self._create_tray_icon('#2196F3')
        self.alert_icon = self._create_tray_icon('#F44336')
        
        self.tray_icon = QSystemTrayIcon(self)
        self.tray_icon.setIcon(self.normal_icon)
        self.tray_icon.setToolTip('智能任务助手')
        
        self.tray_menu = QMenu()
        
        self.show_action = QAction('显示主窗口', self)
        self.show_action.triggered.connect(self._show_window)
        self.tray_menu.addAction(self.show_action)
        
        self.quick_create_action = QAction('⚡ 快速创建任务', self)
        self.quick_create_action.triggered.connect(self._quick_create_task)
        self.tray_menu.addAction(self.quick_create_action)
        
        self.tray_menu.addSeparator()
        
        self.task_menu = QMenu('⏰ 提醒任务')
        self.task_menu.setVisible(False)
        self.tray_menu.addMenu(self.task_menu)
        
        self.tray_menu.addSeparator()
        
        self.quit_action = QAction('退出', self)
        self.quit_action.triggered.connect(self._quit_app)
        self.tray_menu.addAction(self.quit_action)
        
        self.tray_icon.setContextMenu(self.tray_menu)
        self.tray_icon.activated.connect(self._on_tray_activated)
        self.tray_icon.messageClicked.connect(self._on_message_clicked)
        self.tray_icon.show()
    
    def _create_tray_icon(self, color: str) -> QIcon:
        pixmap = QPixmap(64, 64)
        pixmap.fill(Qt.transparent)
        
        from PyQt5.QtGui import QPainter, QBrush, QPen
        painter = QPainter(pixmap)
        painter.setRenderHint(QPainter.Antialiasing)
        
        painter.setBrush(QBrush(QColor(color)))
        painter.setPen(Qt.NoPen)
        painter.drawEllipse(8, 8, 48, 48)
        
        painter.setPen(QPen(QColor('white'), 3))
        font = QFont('Arial', 24, QFont.Bold)
        painter.setFont(font)
        painter.drawText(pixmap.rect(), Qt.AlignCenter, 'T')
        
        painter.end()
        
        return QIcon(pixmap)
    
    def _on_tray_activated(self, reason):
        if reason == QSystemTrayIcon.DoubleClick:
            self._show_window()
    
    def _on_message_clicked(self):
        self._show_window()
    
    def _show_window(self):
        self.show()
        self.activateWindow()
        self.raise_()
    
    def _quit_app(self):
        self.tray_icon.hide()
        self.clipboard.stop_monitoring()
        self.db.close()
        QApplication.quit()
    
    def _init_reminder(self):
        self.reminder_timer = QTimer(self)
        self.reminder_timer.timeout.connect(self._check_upcoming_tasks)
        self.reminder_timer.start(60000)
        
        self.flash_timer = QTimer(self)
        self.flash_timer.timeout.connect(self._flash_icon)
        
        self._check_upcoming_tasks()
    
    def _check_upcoming_tasks(self):
        if not self.config.get('remind_enabled', True):
            return
        
        remind_minutes = self.config.get('remind_minutes', 30)
        now = datetime.now()
        remind_threshold = now + timedelta(minutes=remind_minutes)
        
        tasks = self.db.get_all_tasks()
        upcoming_tasks = []
        
        for task in tasks:
            if task.get('status') in ['completed', 'cancelled']:
                continue
            
            task_id = task.get('task_id')
            
            if task_id in self.confirmed_reminders:
                continue
            
            deadline = task.get('deadline')
            if not deadline:
                continue
            
            try:
                if len(deadline) == 16:
                    deadline_dt = datetime.strptime(deadline, '%Y-%m-%d %H:%M')
                else:
                    deadline_dt = datetime.strptime(deadline, '%Y-%m-%d %H:%M:%S')
                
                if task_id not in self.reminding_tasks:
                    if now < deadline_dt <= remind_threshold:
                        self.reminding_tasks.add(task_id)
                
                if task_id in self.reminding_tasks:
                    upcoming_tasks.append(task)
            except:
                pass
        
        self._update_tray_menu(upcoming_tasks)
        
        if upcoming_tasks:
            self._start_flashing()
            self._show_reminder_notification(upcoming_tasks)
        else:
            self._stop_flashing()
    
    def _update_tray_menu(self, upcoming_tasks):
        self.task_menu.clear()
        
        if upcoming_tasks:
            self.task_menu.setVisible(True)
            self.task_menu.setTitle(f'⏰ 提醒任务 ({len(upcoming_tasks)})')
            
            for task in upcoming_tasks:
                task_id = task.get('task_id')
                title = task.get('title', '未知任务')[:20]
                deadline = task.get('deadline', '')[:16]
                
                action = QAction(f'{title} ({deadline})', self)
                action.setData(task_id)
                action.triggered.connect(lambda checked, tid=task_id: self._open_task_detail(tid))
                self.task_menu.addAction(action)
            
            self.tray_icon.setToolTip(f'智能任务助手 - {len(upcoming_tasks)}个任务即将到期')
        else:
            self.task_menu.setVisible(False)
            self.tray_icon.setToolTip('智能任务助手')
    
    def _open_task_detail(self, task_id):
        self._show_window()
        self._show_task_detail(task_id)
    
    def _start_flashing(self):
        if not self.is_icon_flashing:
            self.is_icon_flashing = True
            self.flash_timer.start(500)
    
    def _stop_flashing(self):
        self.is_icon_flashing = False
        self.flash_timer.stop()
        self.tray_icon.setIcon(self.normal_icon)
    
    def _flash_icon(self):
        if self.flash_state:
            self.tray_icon.setIcon(self.normal_icon)
        else:
            self.tray_icon.setIcon(self.alert_icon)
        self.flash_state = not self.flash_state
    
    def _show_reminder_notification(self, tasks):
        if len(tasks) == 1:
            task = tasks[0]
            title = f"⏰ 任务即将到期"
            message = f"{task.get('title', '未知任务')}\n点击查看详情"
        else:
            title = f"⏰ {len(tasks)}个任务即将到期"
            message = "点击查看任务列表"
        
        self.tray_icon.showMessage(title, message, self.alert_icon, 5000)
    
    def confirm_reminder(self, task_id: str):
        if task_id in self.reminding_tasks:
            self.reminding_tasks.remove(task_id)
        
        self.confirmed_reminders.add(task_id)
        
        if not self.reminding_tasks:
            self._stop_flashing()
        
        self._check_upcoming_tasks()
    
    def closeEvent(self, event):
        event.ignore()
        self.hide()
        self.tray_icon.showMessage(
            '智能任务助手',
            '程序已最小化到系统托盘，双击图标可重新打开',
            self.normal_icon,
            2000
        )
