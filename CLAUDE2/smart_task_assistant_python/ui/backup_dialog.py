"""
数据备份恢复对话框
"""

import os
from datetime import datetime
from PyQt5.QtWidgets import (
    QDialog, QVBoxLayout, QHBoxLayout, QLabel, QPushButton, 
    QFrame, QFileDialog, QMessageBox, QListWidget, QListWidgetItem,
    QGroupBox
)
from PyQt5.QtCore import Qt
from PyQt5.QtGui import QFont

from core.database import DatabaseManager


class BackupDialog(QDialog):
    def __init__(self, parent=None, db: DatabaseManager = None):
        super().__init__(parent)
        
        self.db = db
        
        self.setWindowTitle('💾 数据备份与恢复')
        self.setMinimumSize(500, 450)
        self.setModal(True)
        
        self._init_ui()
        self._load_backups()
    
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
        
        title_label = QLabel('💾 数据备份与恢复')
        title_label.setFont(QFont('Microsoft YaHei', 14, QFont.Bold))
        title_label.setStyleSheet('color: #1976D2;')
        main_layout.addWidget(title_label)
        
        backup_group = QGroupBox('创建备份')
        backup_group.setStyleSheet('''
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
        backup_layout = QVBoxLayout(backup_group)
        
        backup_info = QLabel('备份将保存当前所有任务数据，包括任务信息、标签等。')
        backup_info.setStyleSheet('color: #666;')
        backup_layout.addWidget(backup_info)
        
        backup_btn = QPushButton('💾 创建备份')
        backup_btn.setStyleSheet('''
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
        backup_btn.clicked.connect(self._create_backup)
        backup_layout.addWidget(backup_btn)
        
        main_layout.addWidget(backup_group)
        
        restore_group = QGroupBox('恢复备份')
        restore_group.setStyleSheet('''
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
        restore_layout = QVBoxLayout(restore_group)
        
        restore_info = QLabel('选择一个备份文件进行恢复，恢复将覆盖当前数据。')
        restore_info.setStyleSheet('color: #666;')
        restore_layout.addWidget(restore_info)
        
        self.backup_list = QListWidget()
        self.backup_list.setMinimumHeight(150)
        self.backup_list.setStyleSheet('''
            QListWidget {
                border: 1px solid #ddd;
                border-radius: 6px;
            }
            QListWidget::item {
                padding: 8px;
                border-bottom: 1px solid #eee;
            }
            QListWidget::item:selected {
                background-color: #E3F2FD;
                color: #1976D2;
            }
        ''')
        restore_layout.addWidget(self.backup_list)
        
        restore_btn_layout = QHBoxLayout()
        
        restore_btn = QPushButton('📂 恢复选中')
        restore_btn.setStyleSheet('''
            QPushButton {
                background-color: #FF9800;
                color: white;
                border: none;
                padding: 8px 16px;
                border-radius: 6px;
                font-weight: bold;
            }
            QPushButton:hover {
                background-color: #F57C00;
            }
        ''')
        restore_btn.clicked.connect(self._restore_backup)
        restore_btn_layout.addWidget(restore_btn)
        
        import_btn = QPushButton('📁 从文件导入')
        import_btn.setStyleSheet('''
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
        import_btn.clicked.connect(self._import_backup)
        restore_btn_layout.addWidget(import_btn)
        
        delete_btn = QPushButton('🗑️ 删除选中')
        delete_btn.setStyleSheet('''
            QPushButton {
                background-color: #f5f5f5;
                color: #F44336;
                border: 1px solid #ddd;
                padding: 8px 16px;
                border-radius: 6px;
            }
            QPushButton:hover {
                background-color: #FFEBEE;
            }
        ''')
        delete_btn.clicked.connect(self._delete_backup)
        restore_btn_layout.addWidget(delete_btn)
        
        restore_layout.addLayout(restore_btn_layout)
        
        main_layout.addWidget(restore_group)
        
        main_layout.addStretch()
        
        btn_layout = QHBoxLayout()
        btn_layout.addStretch()
        
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
    
    def _get_backup_dir(self):
        db_path = self.db.db_path
        backup_dir = os.path.join(os.path.dirname(db_path), 'backups')
        if not os.path.exists(backup_dir):
            os.makedirs(backup_dir)
        return backup_dir
    
    def _load_backups(self):
        self.backup_list.clear()
        backup_dir = self._get_backup_dir()
        
        if not os.path.exists(backup_dir):
            return
        
        backups = []
        for f in os.listdir(backup_dir):
            if f.endswith('.db') or f.endswith('.sqlite'):
                file_path = os.path.join(backup_dir, f)
                ctime = os.path.getctime(file_path)
                size = os.path.getsize(file_path)
                backups.append((f, file_path, ctime, size))
        
        backups.sort(key=lambda x: x[2], reverse=True)
        
        for name, path, ctime, size in backups:
            ctime_str = datetime.fromtimestamp(ctime).strftime('%Y-%m-%d %H:%M:%S')
            size_str = self._format_size(size)
            
            item = QListWidgetItem(f'{name}  |  {ctime_str}  |  {size_str}')
            item.setData(Qt.UserRole, path)
            self.backup_list.addItem(item)
        
        if self.backup_list.count() > 0:
            self.backup_list.setCurrentRow(0)
    
    def _format_size(self, size):
        if size < 1024:
            return f'{size} B'
        elif size < 1024 * 1024:
            return f'{size / 1024:.1f} KB'
        else:
            return f'{size / 1024 / 1024:.1f} MB'
    
    def _create_backup(self):
        backup_dir = self._get_backup_dir()
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        backup_name = f'backup_{timestamp}.db'
        backup_path = os.path.join(backup_dir, backup_name)
        
        if self.db.backup_database(backup_path):
            self._load_backups()
            from PyQt5.QtWidgets import QApplication
            QApplication.processEvents()
            QMessageBox.information(self, '备份成功', f'备份已创建:\n{backup_path}')
        else:
            QMessageBox.warning(self, '备份失败', '创建备份失败，请重试')
    
    def _restore_backup(self):
        current_item = self.backup_list.currentItem()
        if not current_item:
            QMessageBox.warning(self, '提示', '请选择要恢复的备份')
            return
        
        backup_path = current_item.data(Qt.UserRole)
        
        reply = QMessageBox.question(
            self, '确认恢复', 
            '恢复备份将覆盖当前所有数据，此操作不可撤销！\n\n确定要继续吗？',
            QMessageBox.Yes | QMessageBox.No, QMessageBox.No
        )
        
        if reply == QMessageBox.Yes:
            if self.db.restore_database(backup_path):
                QMessageBox.information(self, '恢复成功', '数据已恢复，请重启应用程序以生效。')
            else:
                QMessageBox.warning(self, '恢复失败', '恢复备份失败，请重试')
    
    def _import_backup(self):
        file_path, _ = QFileDialog.getOpenFileName(
            self, '选择备份文件', '', '数据库文件 (*.db *.sqlite);;所有文件 (*.*)'
        )
        
        if not file_path:
            return
        
        backup_dir = self._get_backup_dir()
        import shutil
        
        try:
            filename = os.path.basename(file_path)
            if not filename.endswith('.db'):
                filename += '.db'
            
            dest_path = os.path.join(backup_dir, filename)
            shutil.copy2(file_path, dest_path)
            
            QMessageBox.information(self, '导入成功', f'备份文件已导入:\n{dest_path}')
            self._load_backups()
        except Exception as e:
            QMessageBox.warning(self, '导入失败', f'导入失败: {str(e)}')
    
    def _delete_backup(self):
        current_item = self.backup_list.currentItem()
        if not current_item:
            QMessageBox.warning(self, '提示', '请选择要删除的备份')
            return
        
        backup_path = current_item.data(Qt.UserRole)
        
        reply = QMessageBox.question(
            self, '确认删除', 
            f'确定要删除此备份吗？\n\n{os.path.basename(backup_path)}',
            QMessageBox.Yes | QMessageBox.No, QMessageBox.No
        )
        
        if reply == QMessageBox.Yes:
            try:
                os.remove(backup_path)
                self._load_backups()
                QMessageBox.information(self, '删除成功', '备份已删除')
            except Exception as e:
                QMessageBox.warning(self, '删除失败', f'删除失败: {str(e)}')
