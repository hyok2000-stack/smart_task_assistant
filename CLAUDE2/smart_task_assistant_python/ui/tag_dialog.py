"""
标签管理对话框
"""

import uuid
from datetime import datetime
from PyQt5.QtWidgets import (
    QDialog, QVBoxLayout, QHBoxLayout, QLabel, QPushButton, 
    QFrame, QListWidget, QListWidgetItem, QLineEdit, QColorDialog,
    QMessageBox, QInputDialog
)
from PyQt5.QtCore import Qt
from PyQt5.QtGui import QFont, QColor

from core.database import DatabaseManager


class TagManageDialog(QDialog):
    def __init__(self, parent=None, db: DatabaseManager = None):
        super().__init__(parent)
        
        self.db = db
        
        self.setWindowTitle('🏷️ 标签管理')
        self.setMinimumSize(500, 400)
        self.setModal(True)
        
        self._init_ui()
        self._load_tags()
    
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
        
        title_label = QLabel('🏷️ 标签管理')
        title_label.setFont(QFont('Microsoft YaHei', 14, QFont.Bold))
        title_label.setStyleSheet('color: #1976D2;')
        main_layout.addWidget(title_label)
        
        add_frame = QFrame()
        add_frame.setStyleSheet('''
            QFrame {
                background-color: #F5F5F5;
                border-radius: 8px;
                padding: 10px;
            }
        ''')
        add_layout = QHBoxLayout(add_frame)
        
        self.tag_name_input = QLineEdit()
        self.tag_name_input.setPlaceholderText('输入标签名称...')
        self.tag_name_input.setStyleSheet('''
            QLineEdit {
                padding: 8px 12px;
                border: 1px solid #ddd;
                border-radius: 6px;
                font-size: 13px;
            }
        ''')
        add_layout.addWidget(self.tag_name_input, 1)
        
        self.color_btn = QPushButton('🎨 颜色')
        self.color_btn.setStyleSheet('''
            QPushButton {
                background-color: #2196F3;
                color: white;
                border: none;
                padding: 8px 16px;
                border-radius: 6px;
            }
            QPushButton:hover {
                background-color: #1976D2;
            }
        ''')
        self.selected_color = '#2196F3'
        self.color_btn.clicked.connect(self._select_color)
        add_layout.addWidget(self.color_btn)
        
        add_btn = QPushButton('➕ 添加')
        add_btn.setStyleSheet('''
            QPushButton {
                background-color: #4CAF50;
                color: white;
                border: none;
                padding: 8px 16px;
                border-radius: 6px;
                font-weight: bold;
            }
            QPushButton:hover {
                background-color: #388E3C;
            }
        ''')
        add_btn.clicked.connect(self._add_tag)
        add_layout.addWidget(add_btn)
        
        main_layout.addWidget(add_frame)
        
        self.tag_list = QListWidget()
        self.tag_list.setStyleSheet('''
            QListWidget {
                border: 1px solid #ddd;
                border-radius: 8px;
            }
            QListWidget::item {
                padding: 12px;
                border-bottom: 1px solid #eee;
            }
            QListWidget::item:selected {
                background-color: #E3F2FD;
            }
        ''')
        main_layout.addWidget(self.tag_list)
        
        btn_layout = QHBoxLayout()
        btn_layout.addStretch()
        
        edit_btn = QPushButton('✏️ 编辑')
        edit_btn.setStyleSheet('''
            QPushButton {
                background-color: #FF9800;
                color: white;
                border: none;
                padding: 8px 16px;
                border-radius: 6px;
            }
            QPushButton:hover {
                background-color: #F57C00;
            }
        ''')
        edit_btn.clicked.connect(self._edit_tag)
        btn_layout.addWidget(edit_btn)
        
        delete_btn = QPushButton('🗑️ 删除')
        delete_btn.setStyleSheet('''
            QPushButton {
                background-color: #F44336;
                color: white;
                border: none;
                padding: 8px 16px;
                border-radius: 6px;
            }
            QPushButton:hover {
                background-color: #D32F2F;
            }
        ''')
        delete_btn.clicked.connect(self._delete_tag)
        btn_layout.addWidget(delete_btn)
        
        close_btn = QPushButton('关闭')
        close_btn.setStyleSheet('''
            QPushButton {
                background-color: #f5f5f5;
                color: #333;
                border: 1px solid #ddd;
                padding: 8px 16px;
                border-radius: 6px;
            }
            QPushButton:hover {
                background-color: #e0e0e0;
            }
        ''')
        close_btn.clicked.connect(self.accept)
        btn_layout.addWidget(close_btn)
        
        main_layout.addLayout(btn_layout)
    
    def _select_color(self):
        color = QColorDialog.getColor(QColor(self.selected_color), self, '选择标签颜色')
        if color.isValid():
            self.selected_color = color.name()
            self.color_btn.setStyleSheet(f'''
                QPushButton {{
                    background-color: {self.selected_color};
                    color: white;
                    border: none;
                    padding: 8px 16px;
                    border-radius: 6px;
                }}
            ''')
    
    def _load_tags(self):
        self.tag_list.clear()
        tags = self.db.get_all_tags()
        
        for tag in tags:
            item = QListWidgetItem(f"🏷️ {tag['name']}")
            item.setData(Qt.UserRole, tag['tag_id'])
            item.setData(Qt.UserRole + 1, tag['name'])
            item.setData(Qt.UserRole + 2, tag.get('color', '#2196F3'))
            
            color = tag.get('color', '#2196F3')
            item.setForeground(QColor(color))
            
            self.tag_list.addItem(item)
    
    def _add_tag(self):
        name = self.tag_name_input.text().strip()
        if not name:
            QMessageBox.warning(self, '提示', '请输入标签名称')
            return
        
        tag_id = f"TAG{uuid.uuid4().hex[:8].upper()}"
        tag = {
            'tag_id': tag_id,
            'name': name,
            'color': self.selected_color,
            'created_at': datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        }
        
        self.db.insert_tag(tag)
        self.tag_name_input.clear()
        self._load_tags()
        self.statusBar().showMessage(f'✅ 标签 "{name}" 已添加') if hasattr(self, 'statusBar') else None
    
    def _edit_tag(self):
        current_item = self.tag_list.currentItem()
        if not current_item:
            QMessageBox.warning(self, '提示', '请选择要编辑的标签')
            return
        
        tag_id = current_item.data(Qt.UserRole)
        old_name = current_item.data(Qt.UserRole + 1)
        
        new_name, ok = QInputDialog.getText(self, '编辑标签', '标签名称:', text=old_name)
        if ok and new_name.strip():
            self.db.update_tag(tag_id, {'name': new_name.strip()})
            self._load_tags()
    
    def _delete_tag(self):
        current_item = self.tag_list.currentItem()
        if not current_item:
            QMessageBox.warning(self, '提示', '请选择要删除的标签')
            return
        
        tag_id = current_item.data(Qt.UserRole)
        tag_name = current_item.data(Qt.UserRole + 1)
        
        reply = QMessageBox.question(
            self, '确认删除', 
            f'确定要删除标签 "{tag_name}" 吗？\n关联的任务标签也将被移除。',
            QMessageBox.Yes | QMessageBox.No, QMessageBox.No
        )
        
        if reply == QMessageBox.Yes:
            self.db.delete_tag(tag_id)
            self._load_tags()
