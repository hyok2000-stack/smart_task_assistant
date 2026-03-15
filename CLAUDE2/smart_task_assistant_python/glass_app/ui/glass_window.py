"""
毛玻璃风格主窗口
简约清爽的现代UI设计
"""

import uuid
from datetime import datetime, timedelta
from PyQt5.QtWidgets import (
    QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QLabel, QMessageBox, QDialog, QApplication,
    QSystemTrayIcon, QMenu, QAction, QListWidget, QListWidgetItem
)
from PyQt5.QtCore import Qt, QTimer
from PyQt5.QtGui import QFont, QIcon, QPixmap, QColor

import sys
import os

# 添加路径
current_dir = os.path.dirname(os.path.abspath(__file__))
parent_dir = os.path.dirname(current_dir)
root_dir = os.path.dirname(parent_dir)
sys.path.insert(0, root_dir)

from core.database import DatabaseManager
from core.config import Config
from core.recognition import TaskRecognitionService
from core.clipboard import ClipboardService

from glass_app.ui.glass_widgets import (
    GlassWidget, AnimatedBackground, GlassStatCard, GlassTaskCard,
    GlassButton, GlassLineEdit, GlassComboBox, GlassTextEdit,
    GlassScrollArea, GlassHeader, GlassTaskList, GlassDialog
)


class QuickCreateDialog(GlassDialog):
    """快速创建任务对话框"""
    
    def __init__(self, parent, recognition_service):
        super().__init__("⚡ 快速创建任务", parent)
        self.recognition = recognition_service
        self.result_data = None
        self.setMinimumSize(500, 350)
        
        # 说明文字
        desc_label = QLabel("输入任务内容，AI将自动识别标题、时间、优先级等")
        desc_label.setStyleSheet("color: rgba(255,255,255,180); background: transparent; font-size: 13px;")
        self.add_content(desc_label)
        
        # 输入区域
        self.text_edit = GlassTextEdit()
        self.text_edit.setPlaceholderText("例如：明天下午3点前完成项目报告，交给张三，比较紧急")
        self.text_edit.setMaximumHeight(120)
        self.add_content(self.text_edit)
        
        # 按钮
        self.add_button("取消", False)
        self.add_button("✨ 创建", True, self._on_create)
        
    def _on_create(self):
        text = self.text_edit.toPlainText().strip()
        if not text:
            return
            
        self.result_data = text
        self.accept()
        
    def get_task_data(self):
        return self.result_data


class GlassMainWindow(QMainWindow):
    """毛玻璃风格主窗口"""
    
    def __init__(self, db: DatabaseManager, config: Config):
        super().__init__()
        
        self.db = db
        self.config = config
        self.recognition = TaskRecognitionService(
            config={
                'ai_mode': config.get('ai_mode', 'local'),
                'local_llm_address': config.get('local_llm_address', 'http://localhost:11434'),
                'local_llm_model': config.get('local_llm_model', ''),
                'ai_api_key': config.get('ai_api_key', ''),
                'ai_api_base': config.get('ai_api_base', ''),
                'api_model': config.get('api_model', '')
            }
        )
        self.clipboard = ClipboardService()
        
        self.current_status_filter = 'all'
        self.filter_priority = ''
        self.filter_time = ''
        
        self._init_ui()
        self._init_tray()
        self._init_reminder()
        self._load_data()
        
    def _init_ui(self):
        self.setWindowTitle('智能任务助手')
        self.setMinimumSize(1200, 800)
        self.resize(1300, 850)
        
        # 中央部件
        central_widget = QWidget()
        self.setCentralWidget(central_widget)
        
        main_layout = QVBoxLayout(central_widget)
        main_layout.setContentsMargins(0, 0, 0, 0)
        main_layout.setSpacing(0)
        
        # 动态背景
        self.background = AnimatedBackground(self)
        self.background.lower()
        self.background.setGeometry(self.rect())
        
        # 容器
        container = QWidget()
        container.setStyleSheet("background: transparent;")
        layout = QVBoxLayout(container)
        layout.setContentsMargins(30, 30, 30, 30)
        layout.setSpacing(20)
        
        # 头部
        header = self._create_header()
        layout.addWidget(header)
        
        # 统计卡片
        stats = self._create_stats()
        layout.addWidget(stats)
        
        # 搜索和筛选
        filter_widget = self._create_filter()
        layout.addWidget(filter_widget)
        
        # 任务列表
        tasks_widget = self._create_task_list()
        layout.addWidget(tasks_widget, 1)
        
        # 底部操作栏
        actions = self._create_actions()
        layout.addWidget(actions)
        
        # 滚动区域
        scroll = GlassScrollArea()
        scroll.setWidget(container)
        
        main_layout.addWidget(scroll)
        
    def _create_header(self) -> GlassHeader:
        header = GlassHeader(
            "✨ 智能任务助手",
            "让工作更高效，让生活更有序"
        )
        return header
        
    def _create_stats(self) -> QWidget:
        stats_widget = QWidget()
        stats_widget.setStyleSheet("background: transparent;")
        layout = QHBoxLayout(stats_widget)
        layout.setSpacing(15)
        
        # 统计卡片
        self.all_card = GlassStatCard('📋', 0, '全部任务', '#9E9E9E', 'all')
        self.pending_card = GlassStatCard('⏳', 0, '待处理', '#FFA726', 'pending')
        self.in_progress_card = GlassStatCard('🔄', 0, '进行中', '#42A5F5', 'in_progress')
        self.completed_card = GlassStatCard('✅', 0, '已完成', '#66BB6A', 'completed')
        self.overdue_card = GlassStatCard('⚠️', 0, '已逾期', '#EF5350', 'overdue')
        
        # 连接点击信号
        self.all_card.clicked.connect(self._on_stat_card_clicked)
        self.pending_card.clicked.connect(self._on_stat_card_clicked)
        self.in_progress_card.clicked.connect(self._on_stat_card_clicked)
        self.completed_card.clicked.connect(self._on_stat_card_clicked)
        self.overdue_card.clicked.connect(self._on_stat_card_clicked)
        
        layout.addWidget(self.all_card)
        layout.addWidget(self.pending_card)
        layout.addWidget(self.in_progress_card)
        layout.addWidget(self.completed_card)
        layout.addWidget(self.overdue_card)
        
        return stats_widget
        
    def _create_filter(self) -> GlassWidget:
        filter_widget = GlassWidget()
        filter_widget.border_radius = 16
        filter_widget.setFixedHeight(60)
        
        layout = QHBoxLayout(filter_widget)
        layout.setContentsMargins(20, 12, 20, 12)
        layout.setSpacing(15)
        
        # 搜索框
        self.search_input = GlassLineEdit("🔍 搜索任务...")
        self.search_input.textChanged.connect(self._on_search_changed)
        layout.addWidget(self.search_input, 1)
        
        # 优先级筛选
        self.priority_combo = GlassComboBox()
        self.priority_combo.addItem('全部优先级', '')
        self.priority_combo.addItem('🔴 高优先级', 'high')
        self.priority_combo.addItem('🟡 中优先级', 'medium')
        self.priority_combo.addItem('🟢 低优先级', 'low')
        self.priority_combo.setFixedWidth(130)
        self.priority_combo.currentIndexChanged.connect(self._apply_filters)
        layout.addWidget(self.priority_combo)
        
        # 时间筛选
        self.time_combo = GlassComboBox()
        self.time_combo.addItem('全部时间', '')
        self.time_combo.addItem('今天', 'today')
        self.time_combo.addItem('明天', 'tomorrow')
        self.time_combo.addItem('本周', 'this_week')
        self.time_combo.addItem('本月', 'this_month')
        self.time_combo.addItem('已逾期', 'overdue')
        self.time_combo.setFixedWidth(110)
        self.time_combo.currentIndexChanged.connect(self._apply_filters)
        layout.addWidget(self.time_combo)
        
        # 清除筛选按钮
        clear_btn = GlassButton("清除", False)
        clear_btn.clicked.connect(self._clear_filters)
        layout.addWidget(clear_btn)
        
        return filter_widget
        
    def _create_task_list(self) -> GlassWidget:
        tasks_widget = GlassWidget()
        tasks_widget.border_radius = 18
        tasks_widget.glass_color = QColor(255, 255, 255, 20)
        
        layout = QVBoxLayout(tasks_widget)
        layout.setContentsMargins(20, 20, 20, 20)
        layout.setSpacing(12)
        
        # 标题
        title_row = QHBoxLayout()
        title_label = QLabel("📝 任务列表")
        title_label.setStyleSheet("""
            font-size: 16px;
            font-weight: 500;
            color: white;
            background: transparent;
        """)
        title_row.addWidget(title_label)
        
        self.task_count_label = QLabel("共 0 条")
        self.task_count_label.setStyleSheet("""
            font-size: 13px;
            color: rgba(255, 255, 255, 180);
            background: transparent;
        """)
        title_row.addStretch()
        title_row.addWidget(self.task_count_label)
        layout.addLayout(title_row)
        
        # 任务滚动区域
        scroll = GlassScrollArea()
        scroll.setMinimumHeight(300)
        
        self.task_container = QWidget()
        self.task_container.setStyleSheet("background: transparent;")
        self.task_layout = QVBoxLayout(self.task_container)
        self.task_layout.setContentsMargins(0, 0, 0, 0)
        self.task_layout.setSpacing(10)
        self.task_layout.addStretch()
        
        scroll.setWidget(self.task_container)
        layout.addWidget(scroll)
        
        return tasks_widget
        
    def _create_actions(self) -> GlassWidget:
        actions_widget = GlassWidget()
        actions_widget.border_radius = 16
        actions_widget.setFixedHeight(70)
        
        layout = QHBoxLayout(actions_widget)
        layout.setContentsMargins(20, 14, 20, 14)
        layout.setSpacing(15)
        
        # 快速创建按钮
        quick_btn = GlassButton("⚡ 快速创建", False)
        quick_btn.clicked.connect(self._quick_create_task)
        layout.addWidget(quick_btn)
        
        # 新建任务按钮
        new_btn = GlassButton("➕ 新建任务", True)
        new_btn.clicked.connect(self._create_task)
        layout.addWidget(new_btn)
        
        layout.addStretch()
        
        # 其他功能按钮
        stats_btn = GlassButton("📊 统计", False)
        stats_btn.clicked.connect(self._show_stats)
        layout.addWidget(stats_btn)
        
        settings_btn = GlassButton("⚙ 设置", False)
        settings_btn.clicked.connect(self._show_settings)
        layout.addWidget(settings_btn)
        
        return actions_widget
        
    def _load_data(self):
        self._update_stats()
        self._load_tasks()
        
    def _update_stats(self):
        stats = self.db.get_task_stats()
        self.all_card.set_value(stats.get('total', 0))
        self.pending_card.set_value(stats.get('pending', 0))
        self.in_progress_card.set_value(stats.get('in_progress', 0))
        self.completed_card.set_value(stats.get('completed', 0))
        self.overdue_card.set_value(stats.get('overdue', 0))
        
    def _load_tasks(self):
        # 清除现有任务
        while self.task_layout.count() > 1:
            item = self.task_layout.takeAt(0)
            if item.widget():
                item.widget().deleteLater()
        
        # 获取任务
        has_filters = self.filter_priority or self.filter_time
        
        if has_filters or self.current_status_filter != 'all':
            tasks = self.db.get_tasks_by_filters(
                priority=self.filter_priority,
                time_filter=self.filter_time,
                status_filter=self.current_status_filter
            )
        else:
            tasks = self.db.get_all_tasks()
        
        # 显示任务
        for task in tasks:
            card = GlassTaskCard(task)
            card.status_changed.connect(self._on_status_changed)
            card.clicked.connect(self._on_task_clicked)
            self.task_layout.insertWidget(self.task_layout.count() - 1, card)
        
        self.task_count_label.setText(f"共 {len(tasks)} 条")
        
    def _on_stat_card_clicked(self, key: str):
        # 更新选中状态
        self.all_card.set_selected(key == 'all')
        self.pending_card.set_selected(key == 'pending')
        self.in_progress_card.set_selected(key == 'in_progress')
        self.completed_card.set_selected(key == 'completed')
        self.overdue_card.set_selected(key == 'overdue')
        
        self.current_status_filter = key
        self._load_tasks()
        
    def _on_search_changed(self, text: str):
        if not text:
            self._load_tasks()
            return
            
        tasks = self.db.search_tasks(text)
        self._display_tasks(tasks)
        
    def _apply_filters(self):
        self.filter_priority = self.priority_combo.currentData() or ''
        self.filter_time = self.time_combo.currentData() or ''
        self._load_tasks()
        
    def _clear_filters(self):
        self.priority_combo.setCurrentIndex(0)
        self.time_combo.setCurrentIndex(0)
        self.filter_priority = ''
        self.filter_time = ''
        self.current_status_filter = 'all'
        
        # 重置选中状态
        self.all_card.set_selected(True)
        self.pending_card.set_selected(False)
        self.in_progress_card.set_selected(False)
        self.completed_card.set_selected(False)
        self.overdue_card.set_selected(False)
        
        self._load_tasks()
        
    def _display_tasks(self, tasks):
        # 清除现有任务
        while self.task_layout.count() > 1:
            item = self.task_layout.takeAt(0)
            if item.widget():
                item.widget().deleteLater()
        
        # 显示任务
        for task in tasks:
            card = GlassTaskCard(task)
            card.status_changed.connect(self._on_status_changed)
            card.clicked.connect(self._on_task_clicked)
            self.task_layout.insertWidget(self.task_layout.count() - 1, card)
        
        self.task_count_label.setText(f"共 {len(tasks)} 条")
        
    def _on_status_changed(self, task_id: str, status: str):
        self.db.update_task_status(task_id, status)
        self._load_data()
        
    def _on_task_clicked(self, task_id: str):
        # 显示任务详情（简化版：显示消息框）
        task = self.db.get_task_by_id(task_id)
        if task:
            title = task.get('title', '无标题')
            content = task.get('content', '无内容')
            deadline = task.get('deadline', '无截止日期')
            status = task.get('status', 'pending')
            status_names = {'pending': '待处理', 'in_progress': '进行中', 'completed': '已完成', 'cancelled': '已取消'}
            
            QMessageBox.information(
                self, 
                f"任务详情: {title}",
                f"标题: {title}\n\n"
                f"内容: {content}\n\n"
                f"截止日期: {deadline}\n\n"
                f"状态: {status_names.get(status, status)}"
            )
        
    def _quick_create_task(self):
        dialog = QuickCreateDialog(self, self.recognition)
        if dialog.exec_() != QDialog.Accepted:
            return
            
        text = dialog.get_task_data()
        if not text:
            return
        
        # AI识别
        result = self.recognition.recognize(text)
        
        # 创建任务
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
        self._load_data()
        
    def _create_task(self):
        # 简化的创建任务
        from ui.task_create_dialog import TaskCreateDialog
        dialog = TaskCreateDialog(self, self.db, self.recognition)
        if dialog.exec_():
            self._load_data()
            
    def _show_stats(self):
        from ui.stats_dialog import StatsDialog
        dialog = StatsDialog(self, self.db)
        dialog.exec_()
        
    def _show_settings(self):
        from ui.settings_dialog import SettingsDialog
        dialog = SettingsDialog(self, self.config)
        if dialog.exec_():
            self._load_data()
            
    def _init_tray(self):
        # 创建托盘图标
        pixmap = QPixmap(64, 64)
        pixmap.fill(Qt.transparent)
        
        from PyQt5.QtGui import QPainter, QBrush
        painter = QPainter(pixmap)
        painter.setRenderHint(QPainter.Antialiasing)
        painter.setBrush(QBrush(QColor('#667eea')))
        painter.setPen(Qt.NoPen)
        painter.drawEllipse(8, 8, 48, 48)
        painter.setPen(QColor('white'))
        font = QFont('Arial', 24, QFont.Bold)
        painter.setFont(font)
        painter.drawText(pixmap.rect(), Qt.AlignCenter, 'T')
        painter.end()
        
        self.tray_icon = QSystemTrayIcon(self)
        self.tray_icon.setIcon(QIcon(pixmap))
        self.tray_icon.setToolTip('智能任务助手')
        
        # 托盘菜单
        tray_menu = QMenu()
        
        show_action = QAction('显示主窗口', self)
        show_action.triggered.connect(self._show_window)
        tray_menu.addAction(show_action)
        
        quick_action = QAction('⚡ 快速创建任务', self)
        quick_action.triggered.connect(self._quick_create_task)
        tray_menu.addAction(quick_action)
        
        tray_menu.addSeparator()
        
        quit_action = QAction('退出', self)
        quit_action.triggered.connect(self._quit_app)
        tray_menu.addAction(quit_action)
        
        self.tray_icon.setContextMenu(tray_menu)
        self.tray_icon.activated.connect(self._on_tray_activated)
        self.tray_icon.show()
        
    def _on_tray_activated(self, reason):
        if reason == QSystemTrayIcon.DoubleClick:
            self._show_window()
            
    def _show_window(self):
        self.show()
        self.activateWindow()
        self.raise_()
        
    def _quit_app(self):
        self.tray_icon.hide()
        self.db.close()
        QApplication.quit()
        
    def _init_reminder(self):
        self.reminder_timer = QTimer(self)
        self.reminder_timer.timeout.connect(self._check_upcoming_tasks)
        self.reminder_timer.start(60000)  # 每分钟检查一次
        self._check_upcoming_tasks()
        
    def _check_upcoming_tasks(self):
        if not self.config.get('remind_enabled', True):
            return
            
        # 检查即将到期的任务
        overdue_tasks = self.db.get_overdue_tasks()
        
        if overdue_tasks:
            self.tray_icon.showMessage(
                f"⏰ {len(overdue_tasks)}个任务已逾期",
                "点击查看详情",
                self.tray_icon.icon(),
                5000
            )
            
    def resizeEvent(self, event):
        super().resizeEvent(event)
        self.background.setGeometry(self.rect())
        
    def closeEvent(self, event):
        event.ignore()
        self.hide()
        self.tray_icon.showMessage(
            '智能任务助手',
            '程序已最小化到系统托盘，双击图标可重新打开',
            self.tray_icon.icon(),
            2000
        )