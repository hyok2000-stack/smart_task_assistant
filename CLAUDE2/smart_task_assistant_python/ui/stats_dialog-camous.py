"""
统计图表对话框 - 任务完成趋势和效率分析
"""

from datetime import datetime, timedelta
from PyQt5.QtWidgets import (
    QDialog, QVBoxLayout, QHBoxLayout, QLabel, QPushButton, 
    QFrame, QScrollArea, QWidget, QGridLayout, QFileDialog,
    QMessageBox
)
from PyQt5.QtCore import Qt
from PyQt5.QtGui import QFont, QPainter, QColor, QPen, QBrush

from core.database import DatabaseManager


class TrendChartWidget(QWidget):
    def __init__(self, data: list, parent=None):
        super().__init__(parent)
        self.data = data
        self.setMinimumHeight(220)
        self.setMinimumWidth(400)
    
    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        
        width = self.width()
        height = self.height()
        
        margin_left = 50
        margin_right = 20
        margin_top = 20
        margin_bottom = 55
        
        chart_width = width - margin_left - margin_right
        chart_height = height - margin_top - margin_bottom
        
        painter.fillRect(0, 0, width, height, QColor('white'))
        
        painter.setPen(QPen(QColor('#E0E0E0'), 1))
        for i in range(5):
            y = margin_top + chart_height * i // 4
            painter.drawLine(margin_left, y, width - margin_right, y)
        
        if not self.data:
            painter.setPen(QColor('#999'))
            painter.drawText(self.rect(), Qt.AlignCenter, '暂无数据')
            return
        
        max_value = max(max(d.get('completed', 0), d.get('created', 0)) for d in self.data)
        max_value = max(max_value, 1)
        
        bar_width = chart_width // len(self.data) // 3
        group_width = bar_width * 2 + 4
        
        painter.setPen(QPen(QColor('#666')))
        painter.setFont(QFont('Microsoft YaHei', 9))
        
        for i, d in enumerate(self.data):
            x = margin_left + (chart_width - group_width) * i // (len(self.data) - 1) if len(self.data) > 1 else margin_left + chart_width // 2 - group_width // 2
            
            completed_height = d.get('completed', 0) * chart_height // max_value
            created_height = d.get('created', 0) * chart_height // max_value
            
            painter.setBrush(QBrush(QColor('#4CAF50')))
            painter.drawRect(x, margin_top + chart_height - completed_height, bar_width, completed_height)
            
            painter.setBrush(QBrush(QColor('#2196F3')))
            painter.drawRect(x + bar_width + 2, margin_top + chart_height - created_height, bar_width, created_height)
            
            date_str = d.get('date', '')
            if len(date_str) > 5:
                date_str = date_str[5:]
            painter.drawText(x, margin_top + chart_height + 15, date_str)
        
        painter.setPen(QPen(QColor('#666')))
        painter.setFont(QFont('Microsoft YaHei', 8))
        for i in range(5):
            y = margin_top + chart_height * i // 4
            value = max_value * (4 - i) // 4
            painter.drawText(5, y + 5, str(value))
        
        legend_y = height - 5
        painter.setBrush(QBrush(QColor('#4CAF50')))
        painter.drawRect(margin_left, legend_y - 10, 12, 12)
        painter.drawText(margin_left + 16, legend_y, '已完成')
        
        painter.setBrush(QBrush(QColor('#2196F3')))
        painter.drawRect(margin_left + 80, legend_y - 10, 12, 12)
        painter.drawText(margin_left + 96, legend_y, '新建')


class StatsDialog(QDialog):
    def __init__(self, parent=None, db: DatabaseManager = None):
        super().__init__(parent)
        
        self.db = db
        
        self.setWindowTitle('📊 统计分析')
        self.setMinimumSize(700, 600)
        self.setModal(True)
        
        self._init_ui()
    
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
        
        title_label = QLabel('📊 任务统计分析')
        title_label.setFont(QFont('Microsoft YaHei', 16, QFont.Bold))
        title_label.setStyleSheet('color: #1976D2;')
        main_layout.addWidget(title_label)
        
        trend_label = QLabel('📈 近7天任务完成趋势')
        trend_label.setFont(QFont('Microsoft YaHei', 12, QFont.Bold))
        trend_label.setStyleSheet('color: #333; margin-top: 10px;')
        main_layout.addWidget(trend_label)
        
        trend_data = self.db.get_completion_trend(7)
        self.trend_chart = TrendChartWidget(trend_data)
        self.trend_chart.setMinimumHeight(220)
        self.trend_chart.setStyleSheet('border: 1px solid #E0E0E0; border-radius: 8px;')
        main_layout.addWidget(self.trend_chart)
        
        efficiency_label = QLabel('📋 效率分析')
        efficiency_label.setFont(QFont('Microsoft YaHei', 12, QFont.Bold))
        efficiency_label.setStyleSheet('color: #333; margin-top: 10px;')
        main_layout.addWidget(efficiency_label)
        
        efficiency_frame = QFrame()
        efficiency_frame.setStyleSheet('''
            QFrame {
                background-color: #F5F5F5;
                border-radius: 8px;
                padding: 15px;
            }
        ''')
        efficiency_layout = QGridLayout(efficiency_frame)
        efficiency_layout.setSpacing(20)
        
        stats = self.db.get_efficiency_stats()
        
        stat_items = [
            ('完成率', f"{stats.get('completion_rate', 0)}%", '#4CAF50'),
            ('平均完成天数', f"{stats.get('avg_completion_days', 0)}天", '#2196F3'),
            ('逾期率', f"{stats.get('overdue_rate', 0)}%", '#F44336'),
            ('总任务数', str(self.db.get_task_stats().get('total', 0)), '#FF9800'),
        ]
        
        for i, (label, value, color) in enumerate(stat_items):
            stat_widget = QFrame()
            stat_widget.setMinimumHeight(60)
            stat_widget.setStyleSheet(f'''
                QFrame {{
                    background-color: white;
                    border-radius: 8px;
                    border-left: 4px solid {color};
                    padding: 8px 6px;
                }}
            ''')
            stat_layout = QVBoxLayout(stat_widget)
            stat_layout.setSpacing(4)
            stat_layout.setContentsMargins(5, 5, 5, 5)
            
            value_label = QLabel(value)
            value_label.setFont(QFont('Microsoft YaHei', 16, QFont.Bold))
            value_label.setStyleSheet(f'color: {color};')
            value_label.setAlignment(Qt.AlignCenter)
            stat_layout.addWidget(value_label)
            
            name_label = QLabel(label)
            name_label.setStyleSheet('color: #666; font-size: 11px;')
            name_label.setAlignment(Qt.AlignCenter)
            stat_layout.addWidget(name_label)
            
            efficiency_layout.addWidget(stat_widget, i // 2, i % 2)
        
        main_layout.addWidget(efficiency_frame)
        
        priority_label = QLabel('🎯 优先级分布')
        priority_label.setFont(QFont('Microsoft YaHei', 12, QFont.Bold))
        priority_label.setStyleSheet('color: #333; margin-top: 10px;')
        main_layout.addWidget(priority_label)
        
        priority_frame = QFrame()
        priority_frame.setStyleSheet('''
            QFrame {
                background-color: #F5F5F5;
                border-radius: 8px;
                padding: 15px;
            }
        ''')
        priority_layout = QHBoxLayout(priority_frame)
        
        priority_dist = stats.get('priority_distribution', {})
        priority_styles = {
            'high': ('🔴 高优先级', '#F44336'),
            'medium': ('🟡 中优先级', '#FF9800'),
            'low': ('🟢 低优先级', '#4CAF50')
        }
        
        for priority, (name, color) in priority_styles.items():
            count = priority_dist.get(priority, 0)
            p_widget = QLabel(f'{name}: {count}个')
            p_widget.setStyleSheet(f'''
                QLabel {{
                    color: {color};
                    font-weight: bold;
                    padding: 8px 16px;
                    background-color: white;
                    border-radius: 6px;
                }}
            ''')
            priority_layout.addWidget(p_widget)
        
        priority_layout.addStretch()
        main_layout.addWidget(priority_frame)
        
        main_layout.addStretch()
        
        btn_layout = QHBoxLayout()
        btn_layout.addStretch()
        
        export_btn = QPushButton('📥 导出报告')
        export_btn.setStyleSheet('''
            QPushButton {
                background-color: #4CAF50;
                color: white;
                border: none;
                padding: 10px 24px;
                border-radius: 6px;
                font-weight: bold;
            }
            QPushButton:hover {
                background-color: #388E3C;
            }
        ''')
        export_btn.clicked.connect(self._export_report)
        btn_layout.addWidget(export_btn)
        
        close_btn = QPushButton('关闭')
        close_btn.setStyleSheet('''
            QPushButton {
                background-color: #f5f5f5;
                color: #333;
                border: 1px solid #ddd;
                padding: 10px 24px;
                border-radius: 6px;
            }
            QPushButton:hover {
                background-color: #e0e0e0;
            }
        ''')
        close_btn.clicked.connect(self.accept)
        btn_layout.addWidget(close_btn)
        
        main_layout.addLayout(btn_layout)
    
    def _export_report(self):
        file_path, _ = QFileDialog.getSaveFileName(
            self, '导出统计报告', 
            f'任务统计报告_{datetime.now().strftime("%Y%m%d")}.txt',
            '文本文件 (*.txt)'
        )
        
        if not file_path:
            return
        
        try:
            stats = self.db.get_task_stats()
            efficiency = self.db.get_efficiency_stats()
            trend = self.db.get_completion_trend(7)
            
            with open(file_path, 'w', encoding='utf-8') as f:
                f.write('=' * 50 + '\n')
                f.write('智能任务助手 - 统计分析报告\n')
                f.write(f'生成时间: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}\n')
                f.write('=' * 50 + '\n\n')
                
                f.write('【任务统计】\n')
                f.write(f'  总任务数: {stats.get("total", 0)}\n')
                f.write(f'  待处理: {stats.get("pending", 0)}\n')
                f.write(f'  进行中: {stats.get("in_progress", 0)}\n')
                f.write(f'  已完成: {stats.get("completed", 0)}\n')
                f.write(f'  已逾期: {stats.get("overdue", 0)}\n\n')
                
                f.write('【效率分析】\n')
                f.write(f'  完成率: {efficiency.get("completion_rate", 0)}%\n')
                f.write(f'  平均完成天数: {efficiency.get("avg_completion_days", 0)}天\n')
                f.write(f'  逾期率: {efficiency.get("overdue_rate", 0)}%\n\n')
                
                f.write('【近7天趋势】\n')
                for d in trend:
                    f.write(f'  {d.get("date")}: 新建 {d.get("created", 0)}个, 完成 {d.get("completed", 0)}个\n')
            
            QMessageBox.information(self, '导出成功', f'统计报告已导出到:\n{file_path}')
        except Exception as e:
            QMessageBox.warning(self, '导出失败', f'导出失败: {str(e)}')
