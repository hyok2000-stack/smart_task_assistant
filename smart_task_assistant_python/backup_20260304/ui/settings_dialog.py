"""
设置对话框 - 带API测试功能
"""

from PyQt5.QtWidgets import (
    QDialog, QVBoxLayout, QHBoxLayout, QLabel, QLineEdit,
    QPushButton, QComboBox, QFormLayout, QGroupBox, QMessageBox,
    QTextEdit, QCheckBox, QTabWidget, QWidget
)
from PyQt5.QtCore import Qt, QThread, pyqtSignal

from core.config import Config


class APITestThread(QThread):
    test_finished = pyqtSignal(bool, str)
    
    def __init__(self, api_type: str, api_key: str, api_base: str):
        super().__init__()
        self.api_type = api_type
        self.api_key = api_key
        self.api_base = api_base
    
    def run(self):
        try:
            import requests
            
            if self.api_type == 'openai':
                url = f'{self.api_base or "https://api.openai.com/v1"}/models'
                headers = {'Authorization': f'Bearer {self.api_key}'}
                response = requests.get(url, headers=headers, timeout=10)
                
                if response.status_code == 200:
                    self.test_finished.emit(True, 'API连接成功！')
                else:
                    self.test_finished.emit(False, f'API错误: {response.status_code}')
                    
            elif self.api_type == 'qwen':
                url = 'https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation'
                headers = {
                    'Authorization': f'Bearer {self.api_key}',
                    'Content-Type': 'application/json'
                }
                response = requests.post(
                    url,
                    headers=headers,
                    json={
                        'model': 'qwen-turbo',
                        'input': {'messages': [{'role': 'user', 'content': 'hi'}]}
                    },
                    timeout=10
                )
                
                if response.status_code == 200:
                    self.test_finished.emit(True, '通义千问API连接成功！')
                else:
                    self.test_finished.emit(False, f'API错误: {response.text[:100]}')
                    
            elif self.api_type == 'zhipu':
                url = 'https://open.bigmodel.cn/api/paas/v3/model-api/chatglm_lite/invoke'
                headers = {
                    'Authorization': f'Bearer {self.api_key}',
                    'Content-Type': 'application/json'
                }
                response = requests.post(
                    url,
                    headers=headers,
                    json={'prompt': [{'role': 'user', 'content': 'hi'}]},
                    timeout=10
                )
                
                if response.status_code == 200:
                    self.test_finished.emit(True, '智谱API连接成功！')
                else:
                    self.test_finished.emit(False, f'API错误: {response.text[:100]}')
            else:
                self.test_finished.emit(True, '本地模式无需测试')
                
        except Exception as e:
            self.test_finished.emit(False, f'连接失败: {str(e)}')


class SettingsDialog(QDialog):
    def __init__(self, parent, config: Config):
        super().__init__(parent)
        
        self.config = config
        self.test_thread = None
        
        self.setWindowTitle('设置')
        self.setMinimumSize(500, 500)
        
        self._init_ui()
        self._load_settings()
    
    def _init_ui(self):
        layout = QVBoxLayout(self)
        layout.setSpacing(12)
        
        tabs = QTabWidget()
        tabs.setStyleSheet('''
            QTabWidget::pane {
                border: 1px solid #ddd;
                border-radius: 6px;
                padding: 8px;
            }
            QTabBar::tab {
                padding: 8px 16px;
                margin-right: 2px;
            }
            QTabBar::tab:selected {
                background-color: #2196F3;
                color: white;
                border-radius: 4px;
            }
        ''')
        
        ai_tab = QWidget()
        ai_layout = QVBoxLayout(ai_tab)
        ai_layout.setSpacing(12)
        
        ai_group = QGroupBox('🤖 AI识别服务')
        ai_form = QFormLayout(ai_group)
        ai_form.setSpacing(10)
        
        self.api_type_combo = QComboBox()
        self.api_type_combo.addItems([
            'local - 本地规则（免费）',
            'openai - OpenAI GPT',
            'qwen - 通义千问（推荐）',
            'zhipu - 智谱AI'
        ])
        self.api_type_combo.currentIndexChanged.connect(self._on_api_type_changed)
        ai_form.addRow('AI类型:', self.api_type_combo)
        
        self.api_key_edit = QLineEdit()
        self.api_key_edit.setPlaceholderText('输入API密钥')
        self.api_key_edit.setEchoMode(QLineEdit.Password)
        ai_form.addRow('API密钥:', self.api_key_edit)
        
        self.api_base_edit = QLineEdit()
        self.api_base_edit.setPlaceholderText('自定义API地址（可选）')
        ai_form.addRow('API地址:', self.api_base_edit)
        
        test_layout = QHBoxLayout()
        self.test_btn = QPushButton('🔍 测试连接')
        self.test_btn.clicked.connect(self._test_api)
        test_layout.addWidget(self.test_btn)
        test_layout.addStretch()
        ai_form.addRow('', test_layout)
        
        self.test_result = QLabel('')
        self.test_result.setWordWrap(True)
        ai_form.addRow('', self.test_result)
        
        ai_layout.addWidget(ai_group)
        
        help_label = QLabel('''
💡 获取API密钥：
  • 通义千问: dashscope.aliyun.com
  • 智谱AI: open.bigmodel.cn
  • OpenAI: platform.openai.com
        ''')
        help_label.setStyleSheet('color: #666; font-size: 11px;')
        ai_layout.addWidget(help_label)
        ai_layout.addStretch()
        
        tabs.addTab(ai_tab, '🤖 AI服务')
        
        chat_tab = QWidget()
        chat_layout = QVBoxLayout(chat_tab)
        chat_layout.setSpacing(12)
        
        chat_group = QGroupBox('💬 智答AI配置')
        chat_form = QFormLayout(chat_group)
        chat_form.setSpacing(10)
        
        self.chat_api_type_combo = QComboBox()
        self.chat_api_type_combo.addItems([
            'openai - OpenAI GPT',
            'qwen - 通义千问（推荐）',
            'zhipu - 智谱AI'
        ])
        self.chat_api_type_combo.currentIndexChanged.connect(self._on_chat_api_type_changed)
        chat_form.addRow('AI类型:', self.chat_api_type_combo)
        
        self.chat_api_key_edit = QLineEdit()
        self.chat_api_key_edit.setPlaceholderText('输入智答API密钥')
        self.chat_api_key_edit.setEchoMode(QLineEdit.Password)
        chat_form.addRow('API密钥:', self.chat_api_key_edit)
        
        self.chat_api_base_edit = QLineEdit()
        self.chat_api_base_edit.setPlaceholderText('自定义API地址（可选）')
        chat_form.addRow('API地址:', self.chat_api_base_edit)
        
        chat_test_layout = QHBoxLayout()
        self.chat_test_btn = QPushButton('🔍 测试连接')
        self.chat_test_btn.clicked.connect(self._test_chat_api)
        chat_test_layout.addWidget(self.chat_test_btn)
        chat_test_layout.addStretch()
        chat_form.addRow('', chat_test_layout)
        
        self.chat_test_result = QLabel('')
        chat_form.addRow('', self.chat_test_result)
        
        chat_layout.addWidget(chat_group)
        
        chat_help = QLabel('''
💡 智答AI用于对话咨询功能
可使用与任务识别相同或不同的API密钥
        ''')
        chat_help.setStyleSheet('color: #666; font-size: 11px;')
        chat_layout.addWidget(chat_help)
        chat_layout.addStretch()
        
        tabs.addTab(chat_tab, '💬 智答AI')
        
        external_tab = QWidget()
        external_layout = QVBoxLayout(external_tab)
        external_layout.setSpacing(12)
        
        external_group = QGroupBox('📤 外部任务系统')
        external_form = QFormLayout(external_group)
        external_form.setSpacing(10)
        
        self.external_enabled = QCheckBox('启用外部任务系统同步')
        self.external_enabled.stateChanged.connect(self._on_external_enabled_changed)
        external_form.addRow('', self.external_enabled)
        
        self.external_url_edit = QLineEdit()
        self.external_url_edit.setPlaceholderText('例如: https://api.example.com/tasks')
        external_form.addRow('API地址:', self.external_url_edit)
        
        self.external_token_edit = QLineEdit()
        self.external_token_edit.setPlaceholderText('授权令牌')
        self.external_token_edit.setEchoMode(QLineEdit.Password)
        external_form.addRow('授权令牌:', self.external_token_edit)
        
        external_test_layout = QHBoxLayout()
        self.external_test_btn = QPushButton('🔍 测试连接')
        self.external_test_btn.clicked.connect(self._test_external_api)
        external_test_layout.addWidget(self.external_test_btn)
        external_test_layout.addStretch()
        external_form.addRow('', external_test_layout)
        
        self.external_test_result = QLabel('')
        external_form.addRow('', self.external_test_result)
        
        external_layout.addWidget(external_group)
        
        format_group = QGroupBox('📋 同步设置')
        format_form = QFormLayout(format_group)
        
        self.sync_on_create = QCheckBox('创建任务时自动同步')
        format_form.addRow('', self.sync_on_create)
        
        self.sync_on_complete = QCheckBox('完成任务时自动同步')
        format_form.addRow('', self.sync_on_complete)
        
        external_layout.addWidget(format_group)
        external_layout.addStretch()
        
        tabs.addTab(external_tab, '📤 外部系统')
        
        general_tab = QWidget()
        general_layout = QVBoxLayout(general_tab)
        general_layout.setSpacing(12)
        
        general_group = QGroupBox('⚙️ 常规设置')
        general_form = QFormLayout(general_group)
        
        self.clipboard_check = QCheckBox('启用剪贴板监听')
        self.clipboard_check.setStyleSheet('''
            QCheckBox {
                spacing: 8px;
            }
            QCheckBox::indicator {
                width: 18px;
                height: 18px;
            }
        ''')
        general_form.addRow('', self.clipboard_check)
        
        self.auto_start = QCheckBox('开机自动启动')
        general_form.addRow('', self.auto_start)
        
        general_layout.addWidget(general_group)
        
        remind_group = QGroupBox('⏰ 提醒设置')
        remind_form = QFormLayout(remind_group)
        
        self.remind_enabled = QCheckBox('启用任务到期提醒')
        self.remind_enabled.setChecked(True)
        remind_form.addRow('', self.remind_enabled)
        
        remind_time_layout = QHBoxLayout()
        self.remind_minutes = QComboBox()
        self.remind_minutes.addItems(['提前5分钟', '提前10分钟', '提前15分钟', '提前30分钟', '提前1小时', '提前2小时'])
        self.remind_minutes.setCurrentIndex(3)
        remind_time_layout.addWidget(self.remind_minutes)
        remind_time_layout.addStretch()
        remind_form.addRow('提醒时间:', remind_time_layout)
        
        general_layout.addWidget(remind_group)
        general_layout.addStretch()
        
        tabs.addTab(general_tab, '⚙️ 常规')
        
        layout.addWidget(tabs)
        
        button_layout = QHBoxLayout()
        button_layout.addStretch()
        
        cancel_btn = QPushButton('取消')
        cancel_btn.clicked.connect(self.reject)
        button_layout.addWidget(cancel_btn)
        
        save_btn = QPushButton('💾 保存')
        save_btn.clicked.connect(self._save_settings)
        save_btn.setDefault(True)
        button_layout.addWidget(save_btn)
        
        layout.addLayout(button_layout)
    
    def _on_api_type_changed(self, index):
        api_types = ['local', 'openai', 'qwen', 'zhipu']
        is_local = api_types[index] == 'local'
        
        self.api_key_edit.setEnabled(not is_local)
        self.api_base_edit.setEnabled(not is_local)
        self.test_btn.setEnabled(not is_local)
        
        if is_local:
            self.test_result.setText('')
    
    def _on_chat_api_type_changed(self, index):
        api_types = ['openai', 'qwen', 'zhipu']
        self.chat_api_key_edit.setEnabled(True)
        self.chat_api_base_edit.setEnabled(True)
        self.chat_test_btn.setEnabled(True)
    
    def _on_external_enabled_changed(self, state):
        enabled = state == Qt.Checked
        self.external_url_edit.setEnabled(enabled)
        self.external_token_edit.setEnabled(enabled)
        self.external_test_btn.setEnabled(enabled)
        self.sync_on_create.setEnabled(enabled)
        self.sync_on_complete.setEnabled(enabled)
    
    def _load_settings(self):
        api_type = self.config.get('ai_type', 'local')
        api_types = {'local': 0, 'openai': 1, 'qwen': 2, 'zhipu': 3}
        self.api_type_combo.setCurrentIndex(api_types.get(api_type, 0))
        
        self.api_key_edit.setText(self.config.get('ai_api_key', ''))
        self.api_base_edit.setText(self.config.get('ai_api_base', ''))
        self.clipboard_check.setChecked(self.config.get('auto_detect_clipboard', True))
        
        chat_api_type = self.config.get('chat_api_type', 'qwen')
        chat_api_types = {'openai': 0, 'qwen': 1, 'zhipu': 2}
        self.chat_api_type_combo.setCurrentIndex(chat_api_types.get(chat_api_type, 1))
        self.chat_api_key_edit.setText(self.config.get('chat_api_key', ''))
        self.chat_api_base_edit.setText(self.config.get('chat_api_base', ''))
        
        self.external_enabled.setChecked(self.config.get('external_enabled', False))
        self.external_url_edit.setText(self.config.get('external_url', ''))
        self.external_token_edit.setText(self.config.get('external_token', ''))
        self.sync_on_create.setChecked(self.config.get('sync_on_create', True))
        self.sync_on_complete.setChecked(self.config.get('sync_on_complete', True))
        
        self.remind_enabled.setChecked(self.config.get('remind_enabled', True))
        remind_minutes = self.config.get('remind_minutes', 30)
        minute_map = {5: 0, 10: 1, 15: 2, 30: 3, 60: 4, 120: 5}
        self.remind_minutes.setCurrentIndex(minute_map.get(remind_minutes, 3))
        
        self._on_api_type_changed(self.api_type_combo.currentIndex())
        self._on_chat_api_type_changed(self.chat_api_type_combo.currentIndex())
        self._on_external_enabled_changed(Qt.Checked if self.external_enabled.isChecked() else Qt.Unchecked)
    
    def _test_api(self):
        api_types = {0: 'local', 1: 'openai', 2: 'qwen', 3: 'zhipu'}
        api_type = api_types[self.api_type_combo.currentIndex()]
        
        if api_type == 'local':
            self.test_result.setText('✅ 本地模式无需测试')
            self.test_result.setStyleSheet('color: green;')
            return
        
        api_key = self.api_key_edit.text().strip()
        if not api_key:
            self.test_result.setText('❌ 请先输入API密钥')
            self.test_result.setStyleSheet('color: red;')
            return
        
        self.test_btn.setEnabled(False)
        self.test_result.setText('⏳ 正在测试连接...')
        self.test_result.setStyleSheet('color: #666;')
        
        self.test_thread = APITestThread(
            api_type, 
            api_key, 
            self.api_base_edit.text().strip()
        )
        self.test_thread.test_finished.connect(self._on_test_finished)
        self.test_thread.start()
    
    def _test_chat_api(self):
        api_types = {0: 'openai', 1: 'qwen', 2: 'zhipu'}
        api_type = api_types[self.chat_api_type_combo.currentIndex()]
        
        api_key = self.chat_api_key_edit.text().strip()
        if not api_key:
            self.chat_test_result.setText('❌ 请先输入API密钥')
            self.chat_test_result.setStyleSheet('color: red;')
            return
        
        self.chat_test_btn.setEnabled(False)
        self.chat_test_result.setText('⏳ 正在测试连接...')
        self.chat_test_result.setStyleSheet('color: #666;')
        
        self.chat_test_thread = APITestThread(
            api_type, 
            api_key, 
            self.chat_api_base_edit.text().strip()
        )
        self.chat_test_thread.test_finished.connect(self._on_chat_test_finished)
        self.chat_test_thread.start()
    
    def _test_external_api(self):
        url = self.external_url_edit.text().strip()
        token = self.external_token_edit.text().strip()
        
        if not url:
            self.external_test_result.setText('❌ 请输入API地址')
            self.external_test_result.setStyleSheet('color: red;')
            return
        
        self.external_test_btn.setEnabled(False)
        self.external_test_result.setText('⏳ 正在测试连接...')
        self.external_test_result.setStyleSheet('color: #666;')
        
        try:
            import requests
            headers = {'Authorization': f'Bearer {token}'} if token else {}
            response = requests.get(url, headers=headers, timeout=10)
            
            if response.status_code in [200, 201, 401]:
                self.external_test_result.setText('✅ API地址可达')
                self.external_test_result.setStyleSheet('color: green;')
            else:
                self.external_test_result.setText(f'⚠️ 响应码: {response.status_code}')
                self.external_test_result.setStyleSheet('color: orange;')
        except Exception as e:
            self.external_test_result.setText(f'❌ 连接失败: {str(e)}')
            self.external_test_result.setStyleSheet('color: red;')
        finally:
            self.external_test_btn.setEnabled(True)
    
    def _on_test_finished(self, success: bool, message: str):
        self.test_btn.setEnabled(True)
        
        if success:
            self.test_result.setText(f'✅ {message}')
            self.test_result.setStyleSheet('color: green;')
        else:
            self.test_result.setText(f'❌ {message}')
            self.test_result.setStyleSheet('color: red;')
    
    def _on_chat_test_finished(self, success: bool, message: str):
        self.chat_test_btn.setEnabled(True)
        
        if success:
            self.chat_test_result.setText(f'✅ {message}')
            self.chat_test_result.setStyleSheet('color: green;')
        else:
            self.chat_test_result.setText(f'❌ {message}')
            self.chat_test_result.setStyleSheet('color: red;')
    
    def _save_settings(self):
        api_types = {0: 'local', 1: 'openai', 2: 'qwen', 3: 'zhipu'}
        api_type = api_types[self.api_type_combo.currentIndex()]
        
        self.config.set('ai_type', api_type)
        self.config.set('ai_api_key', self.api_key_edit.text().strip())
        self.config.set('ai_api_base', self.api_base_edit.text().strip())
        self.config.set('auto_detect_clipboard', self.clipboard_check.isChecked())
        
        chat_api_types = {0: 'openai', 1: 'qwen', 2: 'zhipu'}
        chat_api_type = chat_api_types[self.chat_api_type_combo.currentIndex()]
        self.config.set('chat_api_type', chat_api_type)
        self.config.set('chat_api_key', self.chat_api_key_edit.text().strip())
        self.config.set('chat_api_base', self.chat_api_base_edit.text().strip())
        
        self.config.set('external_enabled', self.external_enabled.isChecked())
        self.config.set('external_url', self.external_url_edit.text().strip())
        self.config.set('external_token', self.external_token_edit.text().strip())
        self.config.set('sync_on_create', self.sync_on_create.isChecked())
        self.config.set('sync_on_complete', self.sync_on_complete.isChecked())
        
        self.config.set('remind_enabled', self.remind_enabled.isChecked())
        minute_map = {0: 5, 1: 10, 2: 15, 3: 30, 4: 60, 5: 120}
        self.config.set('remind_minutes', minute_map[self.remind_minutes.currentIndex()])
        
        QMessageBox.information(self, '提示', '设置已保存！')
        self.accept()
