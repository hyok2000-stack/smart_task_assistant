"""
毛玻璃风格组件库
简约清爽的现代UI组件
"""

from PyQt5.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QLabel, QPushButton,
    QGraphicsDropShadowEffect, QFrame, QScrollArea, QSpinBox,
    QComboBox, QLineEdit, QTextEdit, QCheckBox, QDateTimeEdit, QDialog
)
from PyQt5.QtCore import Qt, QPropertyAnimation, QEasingCurve, QTimer, pyqtSignal, QSize
from PyQt5.QtGui import (
    QColor, QPainter, QBrush, QPen, QFont, QLinearGradient,
    QPainterPath, QRadialGradient, QPaintEvent
)


class GlassWidget(QWidget):
    """毛玻璃效果基础组件"""
    
    def __init__(self, parent=None):
        super().__init__(parent)
        self.blur_radius = 20
        self.glass_color = QColor(255, 255, 255, 40)
        self.border_color = QColor(255, 255, 255, 80)
        self.border_radius = 20
        self.hover_color = QColor(255, 255, 255, 50)
        self._is_hovered = False
        
    def paintEvent(self, event: QPaintEvent):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        
        # 绘制圆角路径
        path = QPainterPath()
        path.addRoundedRect(0, 0, self.width(), self.height(), 
                           self.border_radius, self.border_radius)
        
        # 填充背景
        fill_color = self.hover_color if self._is_hovered else self.glass_color
        painter.fillPath(path, QBrush(fill_color))
        
        # 绘制边框
        painter.setPen(QPen(self.border_color, 1))
        painter.drawPath(path)
        
    def enterEvent(self, event):
        self._is_hovered = True
        self.update()
        
    def leaveEvent(self, event):
        self._is_hovered = False
        self.update()
        
    def set_glass_color(self, color: QColor):
        self.glass_color = color
        self.update()
        
    def set_border_radius(self, radius: int):
        self.border_radius = radius
        self.update()


class AnimatedBackground(QWidget):
    """动态渐变背景"""
    
    def __init__(self, parent=None):
        super().__init__(parent)
        self.offset = 0
        self.direction = 1
        self._gradient_colors = [
            (QColor(102, 126, 234), QColor(118, 75, 162), QColor(240, 147, 251)),  # 紫粉
            (QColor(66, 165, 245), QColor(41, 121, 255), QColor(30, 136, 229)),  # 蓝色
            (QColor(38, 198, 218), QColor(0, 172, 193), QColor(0, 151, 167)),  # 青色
        ]
        self._current_theme = 0
        
        self.timer = QTimer()
        self.timer.timeout.connect(self.animate)
        self.timer.start(50)
        
    def animate(self):
        self.offset += self.direction * 0.3
        if self.offset >= 100 or self.offset <= 0:
            self.direction *= -1
        self.update()
        
    def paintEvent(self, event: QPaintEvent):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        
        # 创建渐变
        gradient = QLinearGradient(0, 0, self.width(), self.height())
        colors = self._gradient_colors[self._current_theme]
        
        gradient.setColorAt(0, colors[0])
        gradient.setColorAt(0.5, colors[1])
        gradient.setColorAt(1, colors[2])
        
        painter.fillRect(self.rect(), gradient)
        
        # 绘制浮动圆形装饰
        self._draw_floating_shape(painter, 100 + self.offset, 80, 200)
        self._draw_floating_shape(painter, self.width() - 150, 300 + self.offset * 0.5, 150)
        self._draw_floating_shape(painter, 200, self.height() - 150 - self.offset * 0.3, 120)
        self._draw_floating_shape(painter, self.width() - 300, 100 + self.offset * 0.2, 100)
        
    def _draw_floating_shape(self, painter: QPainter, x: float, y: float, size: int):
        gradient = QRadialGradient(x, y, size)
        gradient.setColorAt(0, QColor(255, 255, 255, 30))
        gradient.setColorAt(1, QColor(255, 255, 255, 0))
        
        painter.setBrush(QBrush(gradient))
        painter.setPen(Qt.NoPen)
        painter.drawEllipse(int(x - size/2), int(y - size/2), size, size)
        
    def set_theme(self, theme_index: int):
        if 0 <= theme_index < len(self._gradient_colors):
            self._current_theme = theme_index
            self.update()


class GlassStatCard(GlassWidget):
    """统计卡片"""
    
    clicked = pyqtSignal(str)
    
    def __init__(self, icon: str, value: int, label: str, color: str, key: str, parent=None):
        super().__init__(parent)
        self.key = key
        self.color = color
        self._selected = False
        self.setFixedSize(180, 120)
        self.setCursor(Qt.PointingHandCursor)
        
        layout = QVBoxLayout(self)
        layout.setContentsMargins(20, 16, 20, 16)
        layout.setSpacing(6)
        
        # 图标
        icon_label = QLabel(icon)
        icon_label.setStyleSheet("font-size: 28px; background: transparent;")
        icon_label.setAlignment(Qt.AlignLeft)
        
        # 数值
        self.value_label = QLabel(str(value))
        self.value_label.setStyleSheet(f"""
            font-size: 32px;
            font-weight: bold;
            color: white;
            background: transparent;
        """)
        self.value_label.setAlignment(Qt.AlignLeft)
        
        # 标签
        self.label_label = QLabel(label)
        self.label_label.setStyleSheet("""
            font-size: 12px;
            color: rgba(255, 255, 255, 200);
            background: transparent;
        """)
        self.label_label.setAlignment(Qt.AlignLeft)
        
        layout.addWidget(icon_label)
        layout.addWidget(self.value_label)
        layout.addWidget(self.label_label)
        
        # 添加阴影
        self._add_shadow()
        
    def set_value(self, value: int):
        self.value_label.setText(str(value))
        
    def set_selected(self, selected: bool):
        self._selected = selected
        if selected:
            self.glass_color = QColor(255, 255, 255, 60)
            self.border_color = QColor(255, 255, 255, 150)
        else:
            self.glass_color = QColor(255, 255, 255, 40)
            self.border_color = QColor(255, 255, 255, 80)
        self.update()
        
    def _add_shadow(self):
        shadow = QGraphicsDropShadowEffect()
        shadow.setBlurRadius(15)
        shadow.setColor(QColor(0, 0, 0, 40))
        shadow.setOffset(0, 4)
        self.setGraphicsEffect(shadow)
        
    def mousePressEvent(self, event):
        self.clicked.emit(self.key)


class GlassTaskCard(GlassWidget):
    """任务卡片"""
    
    delete_requested = pyqtSignal(str)
    status_changed = pyqtSignal(str, str)
    clicked = pyqtSignal(str)
    
    def __init__(self, task: dict, parent=None):
        super().__init__(parent)
        self.task = task
        self.task_id = task.get('task_id', '')
        self.border_radius = 14
        self.glass_color = QColor(255, 255, 255, 25)
        self.setFixedHeight(90)
        self.setCursor(Qt.PointingHandCursor)
        
        main_layout = QHBoxLayout(self)
        main_layout.setContentsMargins(18, 14, 18, 14)
        main_layout.setSpacing(12)
        
        # 左侧状态指示器
        status_indicator = self._create_status_indicator()
        main_layout.addWidget(status_indicator)
        
        # 中间内容
        content_layout = QVBoxLayout()
        content_layout.setSpacing(6)
        
        # 标题行
        title_row = QHBoxLayout()
        
        title_label = QLabel(task.get('title', '无标题')[:40])
        title_label.setStyleSheet("""
            font-size: 15px;
            font-weight: 500;
            color: white;
            background: transparent;
        """)
        title_row.addWidget(title_label)
        
        # 优先级标签
        priority = task.get('priority', 'medium')
        priority_colors = {
            'high': '#ff6b6b',
            'medium': '#ffc107',
            'low': '#4caf50'
        }
        priority_names = {'high': '高', 'medium': '中', 'low': '低'}
        
        priority_label = QLabel(priority_names.get(priority, '中'))
        priority_label.setStyleSheet(f"""
            font-size: 11px;
            font-weight: 600;
            color: white;
            background: {priority_colors.get(priority, '#666')};
            border-radius: 10px;
            padding: 3px 10px;
        """)
        title_row.addWidget(priority_label)
        title_row.addStretch()
        
        content_layout.addLayout(title_row)
        
        # 元数据行
        meta_row = QHBoxLayout()
        
        deadline = task.get('deadline', '')
        if deadline:
            date_str = deadline[:16].replace('T', ' ')
            meta_label = QLabel(f"📅 {date_str}")
        else:
            meta_label = QLabel("📅 无截止日期")
            
        meta_label.setStyleSheet("""
            font-size: 12px;
            color: rgba(255, 255, 255, 180);
            background: transparent;
        """)
        meta_row.addWidget(meta_label)
        
        owner = task.get('owner_name', '')
        if owner:
            owner_label = QLabel(f"👤 {owner}")
            owner_label.setStyleSheet("""
                font-size: 12px;
                color: rgba(255, 255, 255, 180);
                background: transparent;
            """)
            meta_row.addWidget(owner_label)
            
        meta_row.addStretch()
        content_layout.addLayout(meta_row)
        
        main_layout.addLayout(content_layout, 1)
        
        # 右侧操作按钮
        action_layout = QVBoxLayout()
        action_layout.setSpacing(4)
        
        # 完成按钮
        status = task.get('status', 'pending')
        if status != 'completed':
            complete_btn = QPushButton("✓")
            complete_btn.setFixedSize(32, 32)
            complete_btn.setStyleSheet("""
                QPushButton {
                    background: rgba(76, 175, 80, 150);
                    color: white;
                    border: none;
                    border-radius: 16px;
                    font-size: 16px;
                }
                QPushButton:hover {
                    background: rgba(76, 175, 80, 220);
                }
            """)
            complete_btn.clicked.connect(lambda: self.status_changed.emit(self.task_id, 'completed'))
            action_layout.addWidget(complete_btn)
        
        main_layout.addLayout(action_layout)
        
        # 添加阴影
        self._add_shadow()
        
    def _create_status_indicator(self) -> QWidget:
        indicator = QWidget()
        indicator.setFixedWidth(4)
        
        status = self.task.get('status', 'pending')
        colors = {
            'pending': '#FFA726',
            'in_progress': '#42A5F5',
            'completed': '#66BB6A',
            'cancelled': '#EF5350'
        }
        
        indicator.setStyleSheet(f"""
            background: {colors.get(status, '#FFA726')};
            border-radius: 2px;
        """)
        return indicator
        
    def _add_shadow(self):
        shadow = QGraphicsDropShadowEffect()
        shadow.setBlurRadius(10)
        shadow.setColor(QColor(0, 0, 0, 30))
        shadow.setOffset(0, 3)
        self.setGraphicsEffect(shadow)
        
    def mousePressEvent(self, event):
        if event.button() == Qt.LeftButton:
            self.clicked.emit(self.task_id)


class GlassButton(QPushButton):
    """毛玻璃按钮"""
    
    def __init__(self, text: str, primary: bool = False, icon: str = "", parent=None):
        super().__init__(f"{icon} {text}" if icon else text, parent)
        self.primary = primary
        self._is_hovered = False
        self.setFixedHeight(42)
        self.setCursor(Qt.PointingHandCursor)
        self._apply_style()
        
    def _apply_style(self):
        if self.primary:
            self.setStyleSheet("""
                QPushButton {
                    background: rgba(255, 255, 255, 240);
                    color: #667eea;
                    border: none;
                    border-radius: 12px;
                    font-size: 14px;
                    font-weight: 500;
                    padding: 0 24px;
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
                    padding: 0 24px;
                }
                QPushButton:hover {
                    background: rgba(255, 255, 255, 60);
                }
            """)
            
        # 添加阴影
        shadow = QGraphicsDropShadowEffect()
        shadow.setBlurRadius(12)
        shadow.setColor(QColor(0, 0, 0, 40))
        shadow.setOffset(0, 3)
        self.setGraphicsEffect(shadow)


class GlassLineEdit(QLineEdit):
    """毛玻璃输入框"""
    
    def __init__(self, placeholder: str = "", parent=None):
        super().__init__(parent)
        self.setPlaceholderText(placeholder)
        self.setFixedHeight(44)
        self.setStyleSheet("""
            QLineEdit {
                background: rgba(255, 255, 255, 30);
                color: white;
                border: 1px solid rgba(255, 255, 255, 60);
                border-radius: 12px;
                padding: 0 16px;
                font-size: 14px;
            }
            QLineEdit::placeholder {
                color: rgba(255, 255, 255, 150);
            }
            QLineEdit:focus {
                border: 1px solid rgba(255, 255, 255, 120);
                background: rgba(255, 255, 255, 40);
            }
        """)


class GlassComboBox(QComboBox):
    """毛玻璃下拉框"""
    
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setFixedHeight(40)
        self.setStyleSheet("""
            QComboBox {
                background: rgba(255, 255, 255, 30);
                color: white;
                border: 1px solid rgba(255, 255, 255, 60);
                border-radius: 10px;
                padding: 0 12px;
                font-size: 13px;
            }
            QComboBox::drop-down {
                border: none;
                width: 30px;
            }
            QComboBox::down-arrow {
                image: none;
                border: none;
            }
            QComboBox QAbstractItemView {
                background: rgba(102, 126, 234, 240);
                color: white;
                border: 1px solid rgba(255, 255, 255, 80);
                border-radius: 10px;
                selection-background-color: rgba(255, 255, 255, 60);
                selection-color: white;
            }
            QComboBox QAbstractItemView::item {
                padding: 8px 12px;
                min-height: 30px;
            }
        """)


class GlassTextEdit(QTextEdit):
    """毛玻璃文本编辑框"""
    
    def __init__(self, placeholder: str = "", parent=None):
        super().__init__(parent)
        self.setPlaceholderText(placeholder)
        self.setStyleSheet("""
            QTextEdit {
                background: rgba(255, 255, 255, 30);
                color: white;
                border: 1px solid rgba(255, 255, 255, 60);
                border-radius: 12px;
                padding: 12px;
                font-size: 14px;
            }
            QTextEdit::placeholder {
                color: rgba(255, 255, 255, 150);
            }
            QTextEdit:focus {
                border: 1px solid rgba(255, 255, 255, 120);
            }
        """)


class GlassScrollArea(QScrollArea):
    """毛玻璃滚动区域"""
    
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWidgetResizable(True)
        self.setStyleSheet("""
            QScrollArea {
                border: none;
                background: transparent;
            }
            QScrollBar:vertical {
                border: none;
                background: rgba(255, 255, 255, 20);
                width: 10px;
                border-radius: 5px;
                margin: 0;
            }
            QScrollBar::handle:vertical {
                background: rgba(255, 255, 255, 60);
                border-radius: 5px;
                min-height: 30px;
            }
            QScrollBar::handle:vertical:hover {
                background: rgba(255, 255, 255, 80);
            }
            QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {
                height: 0px;
            }
            QScrollBar::add-page:vertical, QScrollBar::sub-page:vertical {
                background: transparent;
            }
        """)


class GlassHeader(GlassWidget):
    """毛玻璃头部区域"""
    
    def __init__(self, title: str, subtitle: str = "", parent=None):
        super().__init__(parent)
        self.border_radius = 24
        self.setFixedHeight(100)
        
        layout = QVBoxLayout(self)
        layout.setContentsMargins(30, 20, 30, 20)
        layout.setAlignment(Qt.AlignCenter)
        
        # 标题
        title_label = QLabel(title)
        title_label.setStyleSheet("""
            font-size: 28px;
            font-weight: 300;
            color: white;
            background: transparent;
        """)
        title_label.setAlignment(Qt.AlignCenter)
        
        layout.addWidget(title_label)
        
        if subtitle:
            subtitle_label = QLabel(subtitle)
            subtitle_label.setStyleSheet("""
                font-size: 13px;
                color: rgba(255, 255, 255, 220);
                background: transparent;
            """)
            subtitle_label.setAlignment(Qt.AlignCenter)
            layout.addWidget(subtitle_label)
        
        # 添加阴影
        shadow = QGraphicsDropShadowEffect()
        shadow.setBlurRadius(20)
        shadow.setColor(QColor(0, 0, 0, 50))
        shadow.setOffset(0, 5)
        self.setGraphicsEffect(shadow)


class GlassTaskList(GlassWidget):
    """任务列表容器"""
    
    def __init__(self, title: str, parent=None):
        super().__init__(parent)
        self.border_radius = 18
        self.glass_color = QColor(255, 255, 255, 20)
        
        self.main_layout = QVBoxLayout(self)
        self.main_layout.setContentsMargins(20, 20, 20, 20)
        self.main_layout.setSpacing(12)
        
        # 标题
        title_label = QLabel(title)
        title_label.setStyleSheet("""
            font-size: 16px;
            font-weight: 500;
            color: white;
            background: transparent;
        """)
        self.main_layout.addWidget(title_label)
        
        # 任务容器
        self.task_container = QWidget()
        self.task_container.setStyleSheet("background: transparent;")
        self.task_layout = QVBoxLayout(self.task_container)
        self.task_layout.setContentsMargins(0, 0, 0, 0)
        self.task_layout.setSpacing(10)
        
        self.main_layout.addWidget(self.task_container)
        self.main_layout.addStretch()
        
    def add_task(self, task_card: GlassTaskCard):
        self.task_layout.addWidget(task_card)
        
    def clear_tasks(self):
        while self.task_layout.count():
            item = self.task_layout.takeAt(0)
            if item.widget():
                item.widget().deleteLater()


class GlassDialog(QDialog):
    """毛玻璃对话框基类"""
    
    def __init__(self, title: str, parent=None):
        super().__init__(parent)
        self.setWindowFlags(Qt.FramelessWindowHint | Qt.Dialog)
        self.setAttribute(Qt.WA_TranslucentBackground)
        self.setMinimumSize(400, 300)
        
        # 主容器
        self.container = QWidget(self)
        self.container.setGeometry(0, 0, self.minimumWidth(), self.minimumHeight())
        
        self.main_layout = QVBoxLayout(self.container)
        self.main_layout.setContentsMargins(24, 20, 24, 20)
        self.main_layout.setSpacing(16)
        
        # 标题栏
        title_label = QLabel(title)
        title_label.setStyleSheet("""
            font-size: 18px;
            font-weight: 500;
            color: white;
            background: transparent;
        """)
        self.main_layout.addWidget(title_label)
        
        # 内容区域
        self.content_widget = QWidget()
        self.content_widget.setStyleSheet("background: transparent;")
        self.content_layout = QVBoxLayout(self.content_widget)
        self.content_layout.setContentsMargins(0, 0, 0, 0)
        self.content_layout.setSpacing(12)
        
        self.main_layout.addWidget(self.content_widget)
        
        # 按钮区域
        self.button_layout = QHBoxLayout()
        self.button_layout.addStretch()
        self.main_layout.addLayout(self.button_layout)
        
    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        
        # 绘制圆角背景
        path = QPainterPath()
        path.addRoundedRect(0, 0, self.width(), self.height(), 20, 20)
        
        # 填充背景
        painter.fillPath(path, QBrush(QColor(102, 126, 234, 240)))
        
        # 绘制边框
        painter.setPen(QPen(QColor(255, 255, 255, 80), 1))
        painter.drawPath(path)
        
    def resizeEvent(self, event):
        super().resizeEvent(event)
        if hasattr(self, 'container'):
            self.container.setGeometry(0, 0, self.width(), self.height())
        
    def add_button(self, text: str, primary: bool = False, callback=None):
        btn = GlassButton(text, primary)
        if callback:
            btn.clicked.connect(callback)
        self.button_layout.addWidget(btn)
        return btn
        
    def add_content(self, widget: QWidget):
        self.content_layout.addWidget(widget)
