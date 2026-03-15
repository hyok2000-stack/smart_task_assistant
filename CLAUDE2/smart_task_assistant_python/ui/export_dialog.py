"""
数据导出对话框 - 支持多种格式导出
"""

import csv
import json
from datetime import datetime
from PyQt5.QtWidgets import (
    QDialog, QVBoxLayout, QHBoxLayout, QLabel, QPushButton, 
    QFrame, QRadioButton, QButtonGroup, QFileDialog, QMessageBox,
    QCheckBox, QGroupBox
)
from PyQt5.QtCore import Qt
from PyQt5.QtGui import QFont

from core.database import DatabaseManager


class ExportDialog(QDialog):
    def __init__(self, parent=None, db: DatabaseManager = None, task_ids: list = None):
        super().__init__(parent)
        
        self.db = db
        self.task_ids = task_ids
        
        self.setWindowTitle('📥 数据导出')
        self.setMinimumSize(450, 400)
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
            QRadioButton {
                color: #333;
                padding: 5px;
            }
            QRadioButton::indicator {
                width: 18px;
                height: 18px;
            }
        ''')
        
        main_layout = QVBoxLayout(self)
        main_layout.setSpacing(16)
        main_layout.setContentsMargins(20, 20, 20, 20)
        
        title_label = QLabel('📥 导出任务数据')
        title_label.setFont(QFont('Microsoft YaHei', 14, QFont.Bold))
        title_label.setStyleSheet('color: #1976D2;')
        main_layout.addWidget(title_label)
        
        scope_group = QGroupBox('导出范围')
        scope_group.setStyleSheet('''
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
        scope_layout = QVBoxLayout(scope_group)
        
        self.scope_all = QRadioButton('全部任务')
        self.scope_all.setChecked(True)
        scope_layout.addWidget(self.scope_all)
        
        self.scope_selected = QRadioButton('选中的任务')
        if self.task_ids:
            self.scope_selected.setText(f'选中的任务 ({len(self.task_ids)}个)')
        else:
            self.scope_selected.setEnabled(False)
        scope_layout.addWidget(self.scope_selected)
        
        self.scope_completed = QRadioButton('已完成的任务')
        scope_layout.addWidget(self.scope_completed)
        
        main_layout.addWidget(scope_group)
        
        format_group = QGroupBox('导出格式')
        format_group.setStyleSheet('''
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
        format_layout = QVBoxLayout(format_group)
        
        self.format_csv = QRadioButton('CSV 格式 - 适合Excel打开')
        self.format_csv.setChecked(True)
        format_layout.addWidget(self.format_csv)
        
        self.format_json = QRadioButton('JSON 格式 - 适合程序处理')
        format_layout.addWidget(self.format_json)
        
        self.format_txt = QRadioButton('TXT 文本格式 - 简洁易读')
        format_layout.addWidget(self.format_txt)
        
        self.format_html = QRadioButton('HTML 格式 - 网页展示')
        format_layout.addWidget(self.format_html)
        
        main_layout.addWidget(format_group)
        
        fields_group = QGroupBox('导出字段')
        fields_group.setStyleSheet('''
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
        fields_layout = QHBoxLayout(fields_group)
        
        self.field_title = QCheckBox('标题')
        self.field_title.setChecked(True)
        fields_layout.addWidget(self.field_title)
        
        self.field_content = QCheckBox('内容')
        self.field_content.setChecked(True)
        fields_layout.addWidget(self.field_content)
        
        self.field_status = QCheckBox('状态')
        self.field_status.setChecked(True)
        fields_layout.addWidget(self.field_status)
        
        self.field_deadline = QCheckBox('截止时间')
        self.field_deadline.setChecked(True)
        fields_layout.addWidget(self.field_deadline)
        
        self.field_priority = QCheckBox('优先级')
        self.field_priority.setChecked(True)
        fields_layout.addWidget(self.field_priority)
        
        main_layout.addWidget(fields_group)
        
        main_layout.addStretch()
        
        btn_layout = QHBoxLayout()
        btn_layout.addStretch()
        
        cancel_btn = QPushButton('取消')
        cancel_btn.setStyleSheet('''
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
        cancel_btn.clicked.connect(self.reject)
        btn_layout.addWidget(cancel_btn)
        
        export_btn = QPushButton('📥 导出')
        export_btn.setStyleSheet('''
            QPushButton {
                background-color: #2196F3;
                color: white;
                border: none;
                padding: 10px 24px;
                border-radius: 6px;
                font-weight: bold;
            }
            QPushButton:hover {
                background-color: #1976D2;
            }
        ''')
        export_btn.clicked.connect(self._do_export)
        btn_layout.addWidget(export_btn)
        
        main_layout.addLayout(btn_layout)
    
    def _get_selected_fields(self):
        fields = []
        if self.field_title.isChecked():
            fields.append('title')
        if self.field_content.isChecked():
            fields.append('content')
        if self.field_status.isChecked():
            fields.append('status')
        if self.field_deadline.isChecked():
            fields.append('deadline')
        if self.field_priority.isChecked():
            fields.append('priority')
        return fields
    
    def _get_tasks(self):
        if self.scope_all.isChecked():
            return self.db.export_tasks()
        elif self.scope_selected.isChecked() and self.task_ids:
            return self.db.export_tasks(self.task_ids)
        elif self.scope_completed.isChecked():
            return self.db.get_tasks_by_status('completed')
        return []
    
    def _do_export(self):
        tasks = self._get_tasks()
        if not tasks:
            QMessageBox.warning(self, '提示', '没有可导出的任务')
            return
        
        fields = self._get_selected_fields()
        if not fields:
            QMessageBox.warning(self, '提示', '请至少选择一个导出字段')
            return
        
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        
        if self.format_csv.isChecked():
            file_path, _ = QFileDialog.getSaveFileName(
                self, '导出CSV', f'任务列表_{timestamp}.csv', 'CSV文件 (*.csv)'
            )
            if file_path:
                self._export_csv(tasks, fields, file_path)
        elif self.format_json.isChecked():
            file_path, _ = QFileDialog.getSaveFileName(
                self, '导出JSON', f'任务列表_{timestamp}.json', 'JSON文件 (*.json)'
            )
            if file_path:
                self._export_json(tasks, fields, file_path)
        elif self.format_txt.isChecked():
            file_path, _ = QFileDialog.getSaveFileName(
                self, '导出TXT', f'任务列表_{timestamp}.txt', '文本文件 (*.txt)'
            )
            if file_path:
                self._export_txt(tasks, fields, file_path)
        elif self.format_html.isChecked():
            file_path, _ = QFileDialog.getSaveFileName(
                self, '导出HTML', f'任务列表_{timestamp}.html', 'HTML文件 (*.html)'
            )
            if file_path:
                self._export_html(tasks, fields, file_path)
    
    def _export_csv(self, tasks, fields, file_path):
        try:
            field_names = {
                'title': '标题',
                'content': '内容',
                'status': '状态',
                'deadline': '截止时间',
                'priority': '优先级'
            }
            
            status_names = {
                'pending': '待处理',
                'in_progress': '进行中',
                'completed': '已完成',
                'cancelled': '已取消'
            }
            
            priority_names = {
                'high': '高',
                'medium': '中',
                'low': '低'
            }
            
            with open(file_path, 'w', encoding='utf-8-sig', newline='') as f:
                writer = csv.writer(f)
                writer.writerow([field_names.get(f, f) for f in fields])
                
                for task in tasks:
                    row = []
                    for f in fields:
                        value = task.get(f, '')
                        if f == 'status':
                            value = status_names.get(value, value)
                        elif f == 'priority':
                            value = priority_names.get(value, value)
                        row.append(value)
                    writer.writerow(row)
            
            QMessageBox.information(self, '导出成功', f'已导出 {len(tasks)} 条任务到:\n{file_path}')
            self.accept()
        except Exception as e:
            QMessageBox.warning(self, '导出失败', f'导出失败: {str(e)}')
    
    def _export_json(self, tasks, fields, file_path):
        try:
            export_data = []
            for task in tasks:
                item = {f: task.get(f, '') for f in fields}
                export_data.append(item)
            
            with open(file_path, 'w', encoding='utf-8') as f:
                json.dump(export_data, f, ensure_ascii=False, indent=2)
            
            QMessageBox.information(self, '导出成功', f'已导出 {len(tasks)} 条任务到:\n{file_path}')
            self.accept()
        except Exception as e:
            QMessageBox.warning(self, '导出失败', f'导出失败: {str(e)}')
    
    def _export_txt(self, tasks, fields, file_path):
        try:
            status_names = {
                'pending': '待处理',
                'in_progress': '进行中',
                'completed': '已完成',
                'cancelled': '已取消'
            }
            
            priority_names = {
                'high': '高',
                'medium': '中',
                'low': '低'
            }
            
            field_names = {
                'title': '标题',
                'content': '内容',
                'status': '状态',
                'deadline': '截止时间',
                'priority': '优先级'
            }
            
            with open(file_path, 'w', encoding='utf-8') as f:
                f.write('=' * 50 + '\n')
                f.write(f'任务列表 - 导出时间: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}\n')
                f.write('=' * 50 + '\n\n')
                
                for i, task in enumerate(tasks, 1):
                    f.write(f'【任务 {i}】\n')
                    for field in fields:
                        value = task.get(field, '')
                        if field == 'status':
                            value = status_names.get(value, value)
                        elif field == 'priority':
                            value = priority_names.get(value, value)
                        f.write(f'  {field_names.get(field, field)}: {value}\n')
                    f.write('\n')
            
            QMessageBox.information(self, '导出成功', f'已导出 {len(tasks)} 条任务到:\n{file_path}')
            self.accept()
        except Exception as e:
            QMessageBox.warning(self, '导出失败', f'导出失败: {str(e)}')
    
    def _export_html(self, tasks, fields, file_path):
        try:
            status_names = {
                'pending': '待处理',
                'in_progress': '进行中',
                'completed': '已完成',
                'cancelled': '已取消'
            }
            
            priority_names = {
                'high': '高',
                'medium': '中',
                'low': '低'
            }
            
            field_names = {
                'title': '标题',
                'content': '内容',
                'status': '状态',
                'deadline': '截止时间',
                'priority': '优先级'
            }
            
            html = f'''<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>任务列表</title>
    <style>
        body {{ font-family: Microsoft YaHei, sans-serif; padding: 20px; }}
        h1 {{ color: #1976D2; }}
        table {{ border-collapse: collapse; width: 100%; }}
        th, td {{ border: 1px solid #ddd; padding: 10px; text-align: left; }}
        th {{ background-color: #1976D2; color: white; }}
        tr:nth-child(even) {{ background-color: #f9f9f9; }}
        .footer {{ margin-top: 20px; color: #999; font-size: 12px; }}
    </style>
</head>
<body>
    <h1>📋 任务列表</h1>
    <p>导出时间: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}</p>
    <table>
        <tr>
'''
            
            for field in fields:
                html += f'            <th>{field_names.get(field, field)}</th>\n'
            html += '        </tr>\n'
            
            for task in tasks:
                html += '        <tr>\n'
                for field in fields:
                    value = task.get(field, '')
                    if field == 'status':
                        value = status_names.get(value, value)
                    elif field == 'priority':
                        value = priority_names.get(value, value)
                    html += f'            <td>{value}</td>\n'
                html += '        </tr>\n'
            
            html += '''    </table>
    <div class="footer">智能任务助手 - 湖南高速信息科技有限公司</div>
</body>
</html>'''
            
            with open(file_path, 'w', encoding='utf-8') as f:
                f.write(html)
            
            QMessageBox.information(self, '导出成功', f'已导出 {len(tasks)} 条任务到:\n{file_path}')
            self.accept()
        except Exception as e:
            QMessageBox.warning(self, '导出失败', f'导出失败: {str(e)}')
