"""
智能建议对话框 - AI分析和任务建议
"""

from datetime import datetime
from PyQt5.QtWidgets import (
    QDialog, QVBoxLayout, QHBoxLayout, QLabel, QPushButton, 
    QFrame, QScrollArea, QWidget, QMessageBox
)
from PyQt5.QtCore import Qt, pyqtSignal, QThread, QTimer
from PyQt5.QtGui import QFont

from core.database import DatabaseManager
from core.smart_suggestion import SmartSuggestionService


class SmartSuggestionDialog(QDialog):
    action_triggered = pyqtSignal(str, str)
    
    def __init__(self, parent=None, db: DatabaseManager = None, recognition=None):
        super().__init__(parent)
        
        self.db = db
        self.recognition = recognition
        
        self.setWindowTitle('🤖 智能建议')
        self.setMinimumSize(600, 500)
        self.setModal(True)
        
        self._init_ui()
        
        QTimer.singleShot(100, self._load_suggestions)
    
    def _init_ui(self):
        self.setStyleSheet('''
            QDialog {
                background-color: white;
            }
            QLabel {
                color: #333;
            }
        ''')
        
        main_layout = QVBoxLayout(self)
        main_layout.setSpacing(16)
        main_layout.setContentsMargins(20, 20, 20, 20)
        
        title_label = QLabel('🤖 智能任务建议')
        title_label.setFont(QFont('Microsoft YaHei', 14, QFont.Bold))
        title_label.setStyleSheet('color: #1976D2;')
        main_layout.addWidget(title_label)
        
        self.scroll = QScrollArea()
        self.scroll.setWidgetResizable(True)
        self.scroll.setStyleSheet('''
            QScrollArea {
                border: none;
                background-color: transparent;
            }
        ''')
        
        self.scroll_content = QWidget()
        self.scroll_layout = QVBoxLayout(self.scroll_content)
        self.scroll_layout.setSpacing(12)
        
        self.loading_label = QLabel('🔄 正在分析任务数据，请稍候...')
        self.loading_label.setStyleSheet('color: #2196F3; font-size: 14px; padding: 40px;')
        self.loading_label.setAlignment(Qt.AlignCenter)
        self.scroll_layout.addWidget(self.loading_label)
        
        self.scroll.setWidget(self.scroll_content)
        main_layout.addWidget(self.scroll)
        
        self.daily_plan_frame = QFrame()
        self.daily_plan_layout = QVBoxLayout(self.daily_plan_frame)
        main_layout.addWidget(self.daily_plan_frame)
        
        btn_layout = QHBoxLayout()
        btn_layout.addStretch()
        
        refresh_btn = QPushButton('🔄 刷新建议')
        refresh_btn.setStyleSheet('''
            QPushButton {
                background-color: #2196F3;
                color: white;
                border: none;
                padding: 10px 20px;
                border-radius: 6px;
                font-weight: bold;
            }
            QPushButton:hover {
                background-color: #1976D2;
            }
        ''')
        refresh_btn.clicked.connect(self._refresh)
        btn_layout.addWidget(refresh_btn)
        
        close_btn = QPushButton('关闭')
        close_btn.setStyleSheet('''
            QPushButton {
                background-color: #f5f5f5;
                color: #333;
                border: 1px solid #ddd;
                padding: 10px 20px;
                border-radius: 6px;
            }
            QPushButton:hover {
                background-color: #e0e0e0;
            }
        ''')
        close_btn.clicked.connect(self.accept)
        btn_layout.addWidget(close_btn)
        
        main_layout.addLayout(btn_layout)
    
    def _load_suggestions(self):
        try:
            self.suggestion_service = SmartSuggestionService(self.db, self.recognition)
            suggestions = self.suggestion_service.get_smart_suggestions()
            self._display_suggestions(suggestions)
        except Exception as e:
            import traceback
            traceback.print_exc()
            self.loading_label.setText(f'❌ 加载失败: {str(e)}')
            self.loading_label.setStyleSheet('color: #F44336; font-size: 14px; padding: 40px;')
    
    def _display_suggestions(self, suggestions):
        self.loading_label.hide()
        
        if not suggestions:
            empty_label = QLabel('🎉 太棒了！目前没有特别的建议，继续保持！')
            empty_label.setStyleSheet('color: #4CAF50; font-size: 14px; padding: 20px;')
            empty_label.setAlignment(Qt.AlignCenter)
            self.scroll_layout.addWidget(empty_label)
        else:
            for suggestion in suggestions:
                try:
                    card = self._create_suggestion_card(suggestion)
                    self.scroll_layout.addWidget(card)
                except Exception as e:
                    import traceback
                    traceback.print_exc()
                    print(f"创建建议卡片失败: {e}")
        
        self.scroll_layout.addStretch()
        
        try:
            if hasattr(self, 'suggestion_service') and self.suggestion_service:
                daily_plan = self.suggestion_service.get_daily_plan()
                plan_frame = self._create_daily_plan_card(daily_plan)
                self.daily_plan_layout.addWidget(plan_frame)
        except Exception as e:
            import traceback
            traceback.print_exc()
            print(f"创建每日计划失败: {e}")
    
    def _create_suggestion_card(self, suggestion: dict) -> QFrame:
        card = QFrame()
        
        type_styles = {
            'urgent': ('#F44336', '🚨'),
            'warning': ('#FF9800', '⚠️'),
            'success': ('#4CAF50', '✅'),
            'tip': ('#2196F3', '💡'),
            'info': ('#9E9E9E', 'ℹ️')
        }
        
        color, icon = type_styles.get(suggestion.get('type', 'info'), ('#9E9E9E', 'ℹ️'))
        
        card.setStyleSheet(f'''
            QFrame {{
                background-color: white;
                border: 1px solid #E0E0E0;
                border-radius: 8px;
                border-left: 4px solid {color};
                padding: 12px;
            }}
        ''')
        
        layout = QVBoxLayout(card)
        layout.setSpacing(8)
        
        header_layout = QHBoxLayout()
        
        icon_label = QLabel(icon)
        icon_label.setStyleSheet('font-size: 20px;')
        header_layout.addWidget(icon_label)
        
        title_label = QLabel(suggestion.get('title', ''))
        title_label.setFont(QFont('Microsoft YaHei', 12, QFont.Bold))
        title_label.setStyleSheet(f'color: {color};')
        header_layout.addWidget(title_label, 1)
        
        layout.addLayout(header_layout)
        
        content_label = QLabel(suggestion.get('content', ''))
        content_label.setWordWrap(True)
        content_label.setStyleSheet('color: #666;')
        layout.addWidget(content_label)
        
        priority_tasks = suggestion.get('priority_tasks', [])
        if priority_tasks:
            tasks_frame = QFrame()
            tasks_frame.setStyleSheet('''
                QFrame {
                    background-color: #F5F5F5;
                    border-radius: 6px;
                    padding: 8px;
                    margin-top: 8px;
                }
            ''')
            tasks_layout = QVBoxLayout(tasks_frame)
            tasks_layout.setSpacing(6)
            
            for pt in priority_tasks[:5]:
                task_layout = QHBoxLayout()
                
                order_label = QLabel(f"#{pt.get('suggested_order', 1)}")
                order_label.setStyleSheet('''
                    QLabel {
                        background-color: #2196F3;
                        color: white;
                        font-weight: bold;
                        font-size: 11px;
                        padding: 2px 8px;
                        border-radius: 10px;
                    }
                ''')
                task_layout.addWidget(order_label)
                
                task_title = QLabel(pt.get('title', ''))
                task_title.setStyleSheet('font-weight: bold; color: #333;')
                task_layout.addWidget(task_title, 1)
                
                view_btn = QPushButton('查看')
                view_btn.setStyleSheet('''
                    QPushButton {
                        background-color: #2196F3;
                        color: white;
                        border: none;
                        padding: 2px 10px;
                        border-radius: 3px;
                        font-size: 11px;
                    }
                    QPushButton:hover {
                        background-color: #1976D2;
                    }
                ''')
                task_id = pt.get('task_id')
                if task_id:
                    view_btn.clicked.connect(lambda checked, tid=task_id: self._on_task_clicked(tid))
                task_layout.addWidget(view_btn)
                
                tasks_layout.addLayout(task_layout)
                
                reason_label = QLabel(f"💡 {pt.get('reason', '')}")
                reason_label.setWordWrap(True)
                reason_label.setStyleSheet('color: #666; font-size: 11px; padding-left: 30px;')
                tasks_layout.addWidget(reason_label)
            
            layout.addWidget(tasks_frame)
        
        if suggestion.get('action'):
            action_btn = QPushButton(suggestion['action'])
            action_btn.setStyleSheet(f'''
                QPushButton {{
                    background-color: {color};
                    color: white;
                    border: none;
                    padding: 6px 16px;
                    border-radius: 4px;
                }}
                QPushButton:hover {{
                    background-color: {color}CC;
                }}
            ''')
            action_btn.clicked.connect(lambda checked, s=suggestion: self._on_action_clicked(s))
            layout.addWidget(action_btn)
        
        return card
    
    def _on_task_clicked(self, task_id):
        if task_id:
            self.action_triggered.emit('view_task', str(task_id))
            self.accept()
    
    def _on_action_clicked(self, suggestion: dict):
        action = suggestion.get('action', '')
        suggestion_type = suggestion.get('type', '')
        
        if '逾期' in action or '查看逾期' in action:
            self.action_triggered.emit('filter', 'overdue')
            self.accept()
        elif '高优先级' in action:
            self.action_triggered.emit('filter', 'high')
            self.accept()
        elif '统计' in action or '查看统计' in action:
            self.action_triggered.emit('show_stats', '')
        elif '优先级' in action and '调整' in action:
            self.action_triggered.emit('adjust_priority', '')
        else:
            QMessageBox.information(self, '提示', suggestion.get('content', ''))
    
    def _create_daily_plan_card(self, plan: dict) -> QFrame:
        card = QFrame()
        card.setStyleSheet('''
            QFrame {
                background-color: #F5F5F5;
                border-radius: 8px;
                padding: 8px;
            }
        ''')
        
        layout = QVBoxLayout(card)
        layout.setSpacing(6)
        
        title_label = QLabel('📅 今日计划建议')
        title_label.setFont(QFont('Microsoft YaHei', 11, QFont.Bold))
        title_label.setStyleSheet('color: #1976D2;')
        layout.addWidget(title_label)
        
        stats_layout = QHBoxLayout()
        stats_layout.setSpacing(10)
        
        stats = [
            ('总任务', plan.get('total_tasks', 0), '#9E9E9E'),
            ('高优先级', plan.get('high_count', 0), '#F44336'),
        ]
        
        for name, count, color in stats:
            stat_label = QLabel(f'{name}: {count}')
            stat_label.setStyleSheet(f'''
                QLabel {{
                    color: {color};
                    font-weight: bold;
                    font-size: 11px;
                    padding: 3px 8px;
                    background-color: white;
                    border-radius: 4px;
                }}
            ''')
            stats_layout.addWidget(stat_label)
        
        stats_layout.addStretch()
        layout.addLayout(stats_layout)
        
        return card
    
    def _refresh(self):
        self.close()
        dialog = SmartSuggestionDialog(self.parent(), self.db, self.recognition)
        dialog.exec_()
