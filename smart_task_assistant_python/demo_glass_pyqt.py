"""
PyQt5 毛玻璃效果演示
展示如何在Python中实现现代简约的毛玻璃UI
"""

import sys
from PyQt5.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QLabel, QPushButton, QFrame, QGraphicsDropShadowEffect, QScrollArea
)
from PyQt5.QtCore import Qt, QPropertyAnimation, QEasingCurve, QSize, QTimer
from PyQt5.QtGui import (
    QColor, QPainter, QBrush, QPen, QFont, QLinearGradient,
    QPainterPath, QRadialGradient
)


class GlassWidget(QWidget):
    """毛玻璃效果的基础Widget"""
    
    def __init__(self, parent=None):
        super().__init__(parent)
        self.blur_radius = 20
        self.glass_color = QColor(255, 255, 255, 40)
        self.border_color = QColor(255, 255, 255, 80)
        self.border_radius = 20
        
    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        
        path = QPainterPath()
        path.addRoundedRect(0, 0, self.width(), self.height(), 
                           self.border_radius, self.border_radius)
        
        painter.fillPath(path, QBrush(self.glass_color))
        
        painter.setPen(QPen(self.border_color, 1))
        painter.drawPath(path)


class StatCard(GlassWidget):
    """统计卡片"""
    
    def __init__(self, icon, value, label, parent=None):
        super().__init__(parent)
        self.setFixedSize(220, 140)
        
        layout = QVBoxLayout(self)
        layout.setContentsMargins(20, 20, 20, 20)
        layout.setSpacing(8)
        
        icon_label = QLabel(icon)
        icon_label.setStyleSheet("font-size: 32px; background: transparent;")
        icon_label.setAlignment(Qt.AlignLeft)
        
        value_label = QLabel(str(value))
        value_label.setStyleSheet("""
            font-size: 36px;
            font-weight: bold;
            color: white;
            background: transparent;
        """)
        value_label.setAlignment(Qt.AlignLeft)
        
        label_label = QLabel(label)
        label_label.setStyleSheet("""
            font-size: 13px;
            color: rgba(255, 255, 255, 200);
            background: transparent;
        """)
        label_label.setAlignment(Qt.AlignLeft)
        
        layout.addWidget(icon_label)
        layout.addWidget(value_label)
        layout.addWidget(label_label)


class TaskItem(GlassWidget):
    """任务项"""
    
    def __init__(self, title, priority, date, tag, parent=None):
        super().__init__(parent)
        self.border_radius = 12
        self.glass_color = QColor(255, 255, 255, 25)
        self.setFixedHeight(80)
        
        main_layout = QHBoxLayout(self)
        main_layout.setContentsMargins(15, 12, 15, 12)
        
        left_layout = QVBoxLayout()
        left_layout.setSpacing(5)
        
        title_priority_layout = QHBoxLayout()
        
        title_label = QLabel(title)
        title_label.setStyleSheet("""
            font-size: 14px;
            font-weight: 500;
            color: white;
            background: transparent;
        """)
        
        priority_colors = {
            '高': '#ff6b6b',
            '中': '#ffc107',
            '低': '#4caf50'
        }
        priority_label = QLabel(priority)
        priority_label.setStyleSheet(f"""
            font-size: 11px;
            font-weight: 500;
            color: white;
            background: {priority_colors.get(priority, '#666')};
            border-radius: 10px;
            padding: 3px 10px;
        """)
        
        title_priority_layout.addWidget(title_label)
        title_priority_layout.addWidget(priority_label)
        title_priority_layout.addStretch()
        
        meta_label = QLabel(f"📅 {date}    🏷️ {tag}")
        meta_label.setStyleSheet("""
            font-size: 12px;
            color: rgba(255, 255, 255, 180);
            background: transparent;
        """)
        
        left_layout.addLayout(title_priority_layout)
        left_layout.addWidget(meta_label)
        
        main_layout.addLayout(left_layout)
        
        shadow = QGraphicsDropShadowEffect()
        shadow.setBlurRadius(10)
        shadow.setColor(QColor(0, 0, 0, 30))
        shadow.setOffset(0, 2)
        self.setGraphicsEffect(shadow)
        
    def enterEvent(self, event):
        self.glass_color = QColor(255, 255, 255, 35)
        self.update()
        
    def leaveEvent(self, event):
        self.glass_color = QColor(255, 255, 255, 25)
        self.update()


class ActionButton(QPushButton):
    """操作按钮"""
    
    def __init__(self, icon, text, primary=False, parent=None):
        super().__init__(f"{icon}  {text}", parent)
        self.primary = primary
        self.setFixedHeight(45)
        self.setCursor(Qt.PointingHandCursor)
        
        if primary:
            self.setStyleSheet("""
                QPushButton {
                    background: rgba(255, 255, 255, 240);
                    color: #667eea;
                    border: none;
                    border-radius: 12px;
                    font-size: 14px;
                    font-weight: 500;
                    padding: 0 20px;
                }
                QPushButton:hover {
                    background: rgba(255, 255, 255, 255);
                }
            """)
        else:
            self.setStyleSheet("""
                QPushButton {
                    background: rgba(255, 255, 255, 40);
                    color: white;
                    border: 1px solid rgba(255, 255, 255, 80);
                    border-radius: 12px;
                    font-size: 14px;
                    font-weight: 500;
                    padding: 0 20px;
                }
                QPushButton:hover {
                    background: rgba(255, 255, 255, 60);
                }
            """)
        
        shadow = QGraphicsDropShadowEffect()
        shadow.setBlurRadius(15)
        shadow.setColor(QColor(0, 0, 0, 40))
        shadow.setOffset(0, 3)
        self.setGraphicsEffect(shadow)


class AnimatedBackground(QWidget):
    """动态渐变背景"""
    
    def __init__(self, parent=None):
        super().__init__(parent)
        self.offset = 0
        self.direction = 1
        
        self.timer = QTimer()
        self.timer.timeout.connect(self.animate)
        self.timer.start(50)
        
    def animate(self):
        self.offset += self.direction * 0.5
        if self.offset >= 100 or self.offset <= 0:
            self.direction *= -1
        self.update()
        
    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        
        gradient = QLinearGradient(0, 0, self.width(), self.height())
        
        pos = self.offset / 100.0
        gradient.setColorAt(0, QColor(102, 126, 234))
        gradient.setColorAt(0.5, QColor(118, 75, 162))
        gradient.setColorAt(1, QColor(240, 147, 251))
        
        painter.fillRect(self.rect(), gradient)
        
        self.drawFloatingShape(painter, 100 + self.offset, 80, 200)
        self.drawFloatingShape(painter, self.width() - 150, 300 + self.offset * 0.5, 150)
        self.drawFloatingShape(painter, 200, self.height() - 150 - self.offset * 0.3, 120)
        
    def drawFloatingShape(self, painter, x, y, size):
        gradient = QRadialGradient(x, y, size)
        gradient.setColorAt(0, QColor(255, 255, 255, 30))
        gradient.setColorAt(1, QColor(255, 255, 255, 0))
        
        painter.setBrush(QBrush(gradient))
        painter.setPen(Qt.NoPen)
        painter.drawEllipse(int(x - size/2), int(y - size/2), size, size)


class GlassMainWindow(QMainWindow):
    """毛玻璃效果主窗口"""
    
    def __init__(self):
        super().__init__()
        self.initUI()
        
    def initUI(self):
        self.setWindowTitle('智能任务助手 - PyQt5毛玻璃效果')
        self.setGeometry(100, 100, 1200, 800)
        self.setMinimumSize(1000, 700)
        
        central_widget = QWidget()
        self.setCentralWidget(central_widget)
        
        main_layout = QVBoxLayout(central_widget)
        main_layout.setContentsMargins(0, 0, 0, 0)
        main_layout.setSpacing(0)
        
        self.background = AnimatedBackground(self)
        self.background.lower()
        self.background.setGeometry(self.rect())
        
        container = QWidget()
        container.setStyleSheet("background: transparent;")
        layout = QVBoxLayout(container)
        layout.setContentsMargins(40, 40, 40, 40)
        layout.setSpacing(25)
        
        header = self.createHeader()
        layout.addWidget(header)
        
        stats = self.createStats()
        layout.addWidget(stats)
        
        tasks = self.createTasks()
        layout.addWidget(tasks, 1)
        
        actions = self.createActions()
        layout.addWidget(actions)
        
        scroll = QScrollArea()
        scroll.setWidget(container)
        scroll.setWidgetResizable(True)
        scroll.setStyleSheet("""
            QScrollArea {
                border: none;
                background: transparent;
            }
            QScrollBar:vertical {
                border: none;
                background: rgba(255, 255, 255, 20);
                width: 10px;
                border-radius: 5px;
            }
            QScrollBar::handle:vertical {
                background: rgba(255, 255, 255, 60);
                border-radius: 5px;
                min-height: 20px;
            }
            QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {
                height: 0px;
            }
        """)
        
        main_layout.addWidget(scroll)
        
    def createHeader(self):
        header = GlassWidget()
        header.border_radius = 24
        header.setFixedHeight(120)
        
        layout = QVBoxLayout(header)
        layout.setContentsMargins(30, 25, 30, 25)
        layout.setAlignment(Qt.AlignCenter)
        
        title = QLabel('✨ 智能任务助手')
        title.setStyleSheet("""
            font-size: 32px;
            font-weight: 300;
            color: white;
            background: transparent;
        """)
        title.setAlignment(Qt.AlignCenter)
        
        subtitle = QLabel('让工作更高效，让生活更有序')
        subtitle.setStyleSheet("""
            font-size: 14px;
            color: rgba(255, 255, 255, 230);
            background: transparent;
        """)
        subtitle.setAlignment(Qt.AlignCenter)
        
        layout.addWidget(title)
        layout.addWidget(subtitle)
        
        shadow = QGraphicsDropShadowEffect()
        shadow.setBlurRadius(20)
        shadow.setColor(QColor(0, 0, 0, 50))
        shadow.setOffset(0, 5)
        header.setGraphicsEffect(shadow)
        
        return header
        
    def createStats(self):
        stats_widget = QWidget()
        stats_widget.setStyleSheet("background: transparent;")
        layout = QHBoxLayout(stats_widget)
        layout.setSpacing(15)
        
        stats_data = [
            ('📋', '24', '总任务数'),
            ('⏳', '8', '进行中'),
            ('✅', '16', '已完成'),
            ('🔥', '5', '连续完成天数')
        ]
        
        for icon, value, label in stats_data:
            card = StatCard(icon, value, label)
            layout.addWidget(card)
            
        return stats_widget
        
    def createTasks(self):
        tasks_widget = QWidget()
        tasks_widget.setStyleSheet("background: transparent;")
        layout = QHBoxLayout(tasks_widget)
        layout.setSpacing(20)
        
        today_widget = self.createTaskList('📌 今日待办', [
            ('完成项目报告', '高', '今天 18:00', '工作'),
            ('团队会议准备', '中', '今天 14:00', '会议'),
            ('回复客户邮件', '低', '今天 20:00', '沟通'),
        ])
        layout.addWidget(today_widget)
        
        week_widget = self.createTaskList('🎯 本周目标', [
            ('完成产品原型设计', '高', '周五', '设计'),
            ('学习新技术框架', '中', '周日', '学习'),
            ('健身计划执行', '低', '每天', '健康'),
        ])
        layout.addWidget(week_widget)
        
        return tasks_widget
        
    def createTaskList(self, title, tasks):
        list_widget = GlassWidget()
        list_widget.border_radius = 16
        list_widget.glass_color = QColor(255, 255, 255, 20)
        
        layout = QVBoxLayout(list_widget)
        layout.setContentsMargins(20, 20, 20, 20)
        layout.setSpacing(15)
        
        title_label = QLabel(title)
        title_label.setStyleSheet("""
            font-size: 16px;
            font-weight: 500;
            color: white;
            background: transparent;
        """)
        layout.addWidget(title_label)
        
        for task_data in tasks:
            task = TaskItem(*task_data)
            layout.addWidget(task)
            
        layout.addStretch()
        
        return list_widget
        
    def createActions(self):
        actions_widget = GlassWidget()
        actions_widget.border_radius = 16
        actions_widget.setFixedHeight(80)
        
        layout = QHBoxLayout(actions_widget)
        layout.setContentsMargins(20, 15, 20, 15)
        layout.setSpacing(15)
        
        buttons = [
            ('➕', '新建任务', True),
            ('🎤', '语音输入', False),
            ('🤖', 'AI助手', False),
            ('📊', '统计报告', False),
        ]
        
        for icon, text, primary in buttons:
            btn = ActionButton(icon, text, primary)
            layout.addWidget(btn)
            
        return actions_widget
        
    def resizeEvent(self, event):
        super().resizeEvent(event)
        self.background.setGeometry(self.rect())


def main():
    app = QApplication(sys.argv)
    
    app.setStyle('Fusion')
    
    font = QFont('Microsoft YaHei', 9)
    app.setFont(font)
    
    window = GlassMainWindow()
    window.show()
    
    sys.exit(app.exec_())


if __name__ == '__main__':
    main()
