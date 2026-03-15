"""
设置对话框 - 通用AI配置和本地大模型支持
"""

from PyQt5.QtWidgets import (
    QDialog, QVBoxLayout, QHBoxLayout, QLabel, QLineEdit,
    QPushButton, QComboBox, QFormLayout, QGroupBox, QMessageBox,
    QTextEdit, QCheckBox, QTabWidget, QWidget, QSpinBox, QRadioButton, QButtonGroup, QTextBrowser
)
from PyQt5.QtCore import Qt, QThread, pyqtSignal

from core.config import Config


class APITestThread(QThread):
    test_finished = pyqtSignal(bool, str)
    
    def __init__(self, api_type: str, api_key: str, api_base: str, model: str = ''):
        super().__init__()
        self.api_type = api_type
        self.api_key = api_key
        self.api_base = api_base
        self.model = model
    
    def run(self):
        try:
            import requests
            
            if self.api_type == 'local':
                self.test_finished.emit(True, '本地模式无需测试')
                return
            
            if self.api_type == 'local_llm':
                url = f'{self.api_base}/v1/models'
                try:
                    response = requests.get(url, timeout=5)
                    if response.status_code == 200:
                        self.test_finished.emit(True, '本地大模型服务连接成功！')
                    else:
                        self.test_finished.emit(False, f'连接失败: HTTP {response.status_code}')
                except requests.exceptions.ConnectionError:
                    self.test_finished.emit(False, '无法连接到本地服务，请确认服务已启动')
                except requests.exceptions.Timeout:
                    self.test_finished.emit(False, '连接超时，请检查服务地址')
                return
            
            if self.api_type == 'local_llm_model':
                if not self.model:
                    self.test_finished.emit(False, '请输入模型名称')
                    return
                url = f'{self.api_base}/v1/chat/completions'
                try:
                    response = requests.post(
                        url,
                        json={
                            'model': self.model,
                            'messages': [{'role': 'user', 'content': 'hi'}],
                            'max_tokens': 10
                        },
                        timeout=30
                    )
                    if response.status_code == 200:
                        self.test_finished.emit(True, f'模型 {self.model} 连接成功！')
                    else:
                        error_msg = response.text[:200] if response.text else ''
                        self.test_finished.emit(False, f'模型错误: {response.status_code}\n{error_msg}')
                except requests.exceptions.ConnectionError:
                    self.test_finished.emit(False, '无法连接到服务，请确认服务已启动')
                except requests.exceptions.Timeout:
                    self.test_finished.emit(False, '连接超时，请检查服务状态')
                return
            
            if not self.api_base:
                self.test_finished.emit(False, '请输入API地址')
                return
            
            url = f'{self.api_base}/chat/completions'
            headers = {
                'Authorization': f'Bearer {self.api_key}',
                'Content-Type': 'application/json'
            }
            
            test_model = self.model if self.model else 'gpt-3.5-turbo'
            
            response = requests.post(
                url,
                headers=headers,
                json={
                    'model': test_model,
                    'messages': [{'role': 'user', 'content': 'hi'}],
                    'max_tokens': 10
                },
                timeout=15
            )
            
            if response.status_code == 200:
                self.test_finished.emit(True, f'API连接成功！')
            else:
                error_msg = response.text[:200] if response.text else '未知错误'
                self.test_finished.emit(False, f'API错误: {response.status_code}\n{error_msg}')
                
        except requests.exceptions.ConnectionError:
            self.test_finished.emit(False, '无法连接到API地址，请检查地址是否正确')
        except requests.exceptions.Timeout:
            self.test_finished.emit(False, '连接超时，请检查网络或API地址')
        except Exception as e:
            self.test_finished.emit(False, f'连接失败: {str(e)}')


class SettingsDialog(QDialog):
    def __init__(self, parent, config: Config):
        super().__init__(parent)
        
        self.config = config
        self.test_thread = None
        self.chat_test_thread = None
        
        self.setWindowTitle('设置')
        self.setMinimumSize(600, 600)
        
        self._init_ui()
        self._load_settings()
    
    def _init_ui(self):
        self.setStyleSheet('''
            QDialog {
                background-color: white;
            }
            QLabel {
                color: #333;
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
            QLineEdit {
                padding: 8px 12px;
                border: 1px solid #ddd;
                border-radius: 6px;
                background-color: white;
            }
            QLineEdit:focus {
                border-color: #2196F3;
            }
            QTextEdit {
                border: 1px solid #ddd;
                border-radius: 6px;
                background-color: white;
            }
            QTextEdit:focus {
                border-color: #2196F3;
            }
            QComboBox {
                padding: 6px 12px;
                border: 1px solid #ddd;
                border-radius: 6px;
                background-color: white;
            }
            QComboBox:focus {
                border-color: #2196F3;
            }
            QComboBox QAbstractItemView {
                background-color: white;
                color: #333;
                selection-background-color: #E3F2FD;
                selection-color: #333;
            }
            QComboBox QAbstractItemView::item {
                color: #333;
                padding: 4px 8px;
            }
            QSpinBox {
                padding: 6px 12px;
                border: 1px solid #ddd;
                border-radius: 6px;
                background-color: white;
            }
            QSpinBox:focus {
                border-color: #2196F3;
            }
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
            QTabBar::tab:!selected {
                background-color: #f5f5f5;
            }
            QCheckBox {
                spacing: 6px;
            }
            QRadioButton {
                spacing: 6px;
            }
        ''')
        
        layout = QVBoxLayout(self)
        layout.setSpacing(12)
        
        tabs = QTabWidget()
        
        ai_tab = QWidget()
        ai_layout = QVBoxLayout(ai_tab)
        ai_layout.setSpacing(12)
        
        ai_group = QGroupBox('🤖 AI识别服务')
        ai_form = QFormLayout(ai_group)
        ai_form.setSpacing(10)
        
        self.ai_mode_group = QButtonGroup()
        
        self.local_mode_radio = QRadioButton('本地规则模式（免费，无需配置）')
        self.local_mode_radio.setToolTip('使用本地规则引擎进行任务识别，无需API密钥')
        self.ai_mode_group.addButton(self.local_mode_radio, 0)
        ai_form.addRow('服务模式:', self.local_mode_radio)
        
        self.local_llm_mode_radio = QRadioButton('本地大模型服务')
        self.local_llm_mode_radio.setToolTip('使用本地部署的大模型服务（如Ollama、LM Studio等）')
        self.ai_mode_group.addButton(self.local_llm_mode_radio, 1)
        ai_form.addRow('', self.local_llm_mode_radio)
        
        self.remote_api_mode_radio = QRadioButton('远程API服务')
        self.remote_api_mode_radio.setToolTip('使用云端AI服务商的API')
        self.ai_mode_group.addButton(self.remote_api_mode_radio, 2)
        ai_form.addRow('', self.remote_api_mode_radio)
        
        self.ai_mode_group.buttonClicked.connect(self._on_ai_mode_changed)
        
        self.local_llm_group = QGroupBox('本地大模型配置')
        local_llm_form = QFormLayout(self.local_llm_group)
        
        self.local_llm_service_combo = QComboBox()
        self.local_llm_service_combo.addItems([
            'Ollama',
            'LM Studio',
            'vLLM',
            'Text Generation WebUI',
            '其他（自定义）'
        ])
        self.local_llm_service_combo.currentIndexChanged.connect(self._on_local_llm_service_changed)
        local_llm_form.addRow('服务类型:', self.local_llm_service_combo)
        
        self.local_llm_address = QLineEdit()
        self.local_llm_address.setPlaceholderText('例如: http://localhost:11434')
        local_llm_form.addRow('服务地址（必填）:', self.local_llm_address)
        
        self.local_llm_model = QLineEdit()
        self.local_llm_model.setPlaceholderText('例如: qwen2.5:7b, llama3.1:8b')
        local_llm_form.addRow('模型名称（必填）:', self.local_llm_model)
        
        local_llm_test_layout = QHBoxLayout()
        self.local_llm_test_btn = QPushButton('🔍 测试连接')
        self.local_llm_test_btn.clicked.connect(self._test_local_llm)
        self.local_llm_test_btn.setMinimumHeight(32)
        local_llm_test_layout.addWidget(self.local_llm_test_btn)
        local_llm_test_layout.addStretch()
        local_llm_form.addRow('', local_llm_test_layout)
        
        self.local_llm_test_result = QLabel('')
        self.local_llm_test_result.setWordWrap(True)
        self.local_llm_test_result.setMinimumHeight(20)
        local_llm_form.addRow('', self.local_llm_test_result)
        
        ai_form.addRow('', self.local_llm_group)
        
        self.remote_api_group = QGroupBox('远程API配置')
        remote_api_form = QFormLayout(self.remote_api_group)
        remote_api_form.setSpacing(15)
        remote_api_form.setContentsMargins(10, 15, 10, 15)
        
        self.api_service_name = QLineEdit()
        self.api_service_name.setPlaceholderText('例如: OpenAI、通义千问、智谱AI等')
        self.api_service_name.setMinimumHeight(30)
        remote_api_form.addRow('服务名称:', self.api_service_name)
        
        self.api_key_edit = QLineEdit()
        self.api_key_edit.setPlaceholderText('输入API密钥')
        self.api_key_edit.setEchoMode(QLineEdit.Password)
        self.api_key_edit.setMinimumHeight(30)
        remote_api_form.addRow('API密钥（必填）:', self.api_key_edit)
        
        self.api_base_edit = QLineEdit()
        self.api_base_edit.setPlaceholderText('例如: https://api.openai.com/v1 (注意:不要以/结尾)')
        self.api_base_edit.setMinimumHeight(30)
        remote_api_form.addRow('API地址（必填）:', self.api_base_edit)
        
        self.api_model_edit = QLineEdit()
        self.api_model_edit.setPlaceholderText('例如: gpt-3.5-turbo, qwen-turbo, glm-4')
        self.api_model_edit.setMinimumHeight(30)
        remote_api_form.addRow('模型名称（必填）:', self.api_model_edit)
        
        test_layout = QHBoxLayout()
        self.test_btn = QPushButton('🔍 测试连接')
        self.test_btn.clicked.connect(self._test_api)
        self.test_btn.setMinimumHeight(32)
        test_layout.addWidget(self.test_btn)
        test_layout.addStretch()
        remote_api_form.addRow('', test_layout)
        
        self.test_result = QLabel('')
        self.test_result.setWordWrap(True)
        self.test_result.setMinimumHeight(20)
        remote_api_form.addRow('', self.test_result)
        
        ai_form.addRow('', self.remote_api_group)
        
        ai_layout.addWidget(ai_group)
        
        help_label = QTextBrowser()
        help_label.setReadOnly(True)
        help_label.setMaximumHeight(150)
        help_label.setOpenExternalLinks(True)
        help_label.setHtml('''
<b>💡 获取API密钥指引：</b><br>
• <b>OpenAI</b>: <a href="https://platform.openai.com/api-keys">https://platform.openai.com/api-keys</a><br>
  &nbsp;&nbsp;API地址: https://api.openai.com/v1<br>
• <b>通义千问</b>: <a href="https://dashscope.console.aliyun.com/apiKey">https://dashscope.console.aliyun.com/apiKey</a><br>
  &nbsp;&nbsp;API地址: https://dashscope.aliyuncs.com/compatible-mode/v1<br>
• <b>智谱AI</b>: <a href="https://open.bigmodel.cn/api-keys">https://open.bigmodel.cn/api-keys</a><br>
  &nbsp;&nbsp;API地址: https://open.bigmodel.cn/api/paas/v4<br>
• <b>Kimi</b>: <a href="https://platform.moonshot.cn/console/api-keys">https://platform.moonshot.cn/console/api-keys</a><br>
  &nbsp;&nbsp;API地址: https://api.moonshot.cn/v1<br>
• <b>DeepSeek</b>: <a href="https://platform.deepseek.com/api_keys">https://platform.deepseek.com/api_keys</a><br>
  &nbsp;&nbsp;API地址: https://api.deepseek.com/v1<br>
• <b>本地模型</b>: <a href="https://ollama.com">https://ollama.com</a> | <a href="https://lmstudio.ai">https://lmstudio.ai</a><br>
  &nbsp;&nbsp;Ollama地址: http://localhost:11434
        ''')
        help_label.setStyleSheet('''
            QTextBrowser {
                color: #666;
                font-size: 11px;
                border: 1px solid #ddd;
                border-radius: 4px;
                padding: 8px;
                background-color: #f9f9f9;
            }
        ''')
        ai_layout.addWidget(help_label)
        ai_layout.addStretch()
        
        tabs.addTab(ai_tab, '🤖 AI服务')
        
        chat_tab = QWidget()
        chat_layout = QVBoxLayout(chat_tab)
        chat_layout.setSpacing(12)
        
        chat_group = QGroupBox('💬 智答AI配置')
        chat_form = QFormLayout(chat_group)
        chat_form.setSpacing(10)
        
        self.chat_mode_group = QButtonGroup()
        
        self.chat_local_llm_radio = QRadioButton('本地大模型服务')
        self.chat_mode_group.addButton(self.chat_local_llm_radio, 1)
        chat_form.addRow('服务模式:', self.chat_local_llm_radio)
        
        self.chat_remote_api_radio = QRadioButton('远程API服务')
        self.chat_mode_group.addButton(self.chat_remote_api_radio, 2)
        chat_form.addRow('', self.chat_remote_api_radio)
        
        self.chat_mode_group.buttonClicked.connect(self._on_chat_mode_changed)
        
        self.chat_local_llm_group = QGroupBox('本地大模型配置')
        chat_local_llm_form = QFormLayout(self.chat_local_llm_group)
        
        self.chat_local_llm_service_combo = QComboBox()
        self.chat_local_llm_service_combo.addItems([
            'Ollama',
            'LM Studio',
            'vLLM',
            'Text Generation WebUI',
            '其他（自定义）'
        ])
        self.chat_local_llm_service_combo.currentIndexChanged.connect(self._on_chat_local_llm_service_changed)
        chat_local_llm_form.addRow('服务类型:', self.chat_local_llm_service_combo)
        
        self.chat_local_llm_address = QLineEdit()
        self.chat_local_llm_address.setPlaceholderText('例如: http://localhost:11434')
        chat_local_llm_form.addRow('服务地址（必填）:', self.chat_local_llm_address)
        
        self.chat_local_llm_model = QLineEdit()
        self.chat_local_llm_model.setPlaceholderText('例如: qwen2.5:7b, llama3.1:8b')
        chat_local_llm_form.addRow('模型名称（必填）:', self.chat_local_llm_model)
        
        chat_local_llm_test_layout = QHBoxLayout()
        self.chat_local_llm_test_btn = QPushButton('🔍 测试连接')
        self.chat_local_llm_test_btn.clicked.connect(self._test_chat_local_llm)
        self.chat_local_llm_test_btn.setMinimumHeight(32)
        chat_local_llm_test_layout.addWidget(self.chat_local_llm_test_btn)
        chat_local_llm_test_layout.addStretch()
        chat_local_llm_form.addRow('', chat_local_llm_test_layout)
        
        self.chat_local_llm_test_result = QLabel('')
        self.chat_local_llm_test_result.setWordWrap(True)
        self.chat_local_llm_test_result.setMinimumHeight(20)
        chat_local_llm_form.addRow('', self.chat_local_llm_test_result)
        
        chat_form.addRow('', self.chat_local_llm_group)
        
        self.chat_remote_api_group = QGroupBox('远程API配置')
        chat_remote_api_form = QFormLayout(self.chat_remote_api_group)
        chat_remote_api_form.setSpacing(15)
        chat_remote_api_form.setContentsMargins(10, 15, 10, 15)
        
        self.chat_api_service_name = QLineEdit()
        self.chat_api_service_name.setPlaceholderText('例如: OpenAI、通义千问、智谱AI等')
        self.chat_api_service_name.setMinimumHeight(30)
        chat_remote_api_form.addRow('服务名称:', self.chat_api_service_name)
        
        self.chat_api_key_edit = QLineEdit()
        self.chat_api_key_edit.setPlaceholderText('输入智答API密钥')
        self.chat_api_key_edit.setEchoMode(QLineEdit.Password)
        self.chat_api_key_edit.setMinimumHeight(30)
        chat_remote_api_form.addRow('API密钥（必填）:', self.chat_api_key_edit)
        
        self.chat_api_base_edit = QLineEdit()
        self.chat_api_base_edit.setPlaceholderText('例如: https://api.openai.com/v1 (注意:不要以/结尾)')
        self.chat_api_base_edit.setMinimumHeight(30)
        chat_remote_api_form.addRow('API地址（必填）:', self.chat_api_base_edit)
        
        self.chat_api_model_edit = QLineEdit()
        self.chat_api_model_edit.setPlaceholderText('例如: gpt-3.5-turbo, qwen-turbo, glm-4')
        self.chat_api_model_edit.setMinimumHeight(30)
        chat_remote_api_form.addRow('模型名称（必填）:', self.chat_api_model_edit)
        
        chat_test_layout = QHBoxLayout()
        self.chat_test_btn = QPushButton('🔍 测试连接')
        self.chat_test_btn.clicked.connect(self._test_chat_api)
        self.chat_test_btn.setMinimumHeight(32)
        chat_test_layout.addWidget(self.chat_test_btn)
        chat_test_layout.addStretch()
        chat_remote_api_form.addRow('', chat_test_layout)
        
        self.chat_test_result = QLabel('')
        self.chat_test_result.setWordWrap(True)
        self.chat_test_result.setMinimumHeight(20)
        chat_remote_api_form.addRow('', self.chat_test_result)
        
        chat_form.addRow('', self.chat_remote_api_group)
        
        chat_layout.addWidget(chat_group)
        
        chat_help = QTextBrowser()
        chat_help.setReadOnly(True)
        chat_help.setMaximumHeight(180)
        chat_help.setOpenExternalLinks(True)
        chat_help.setHtml('''
<b>💡 智答AI用于对话咨询功能</b><br>
可使用与任务识别相同或不同的配置<br><br>

<b>🔑 获取API密钥指引：</b><br>
• <b>OpenAI</b>: <a href="https://platform.openai.com/api-keys">https://platform.openai.com/api-keys</a><br>
• <b>通义千问</b>: <a href="https://dashscope.console.aliyun.com/apiKey">https://dashscope.console.aliyun.com/apiKey</a><br>
• <b>智谱AI</b>: <a href="https://open.bigmodel.cn/api-keys">https://open.bigmodel.cn/api-keys</a><br>
• <b>Kimi</b>: <a href="https://platform.moonshot.cn/console/api-keys">https://platform.moonshot.cn/console/api-keys</a><br>
• <b>豆包</b>: <a href="https://console.volcengine.com/ark/region:ark+cn-beijing/apiKey">https://console.volcengine.com/ark/apiKey</a><br>
• <b>DeepSeek</b>: <a href="https://platform.deepseek.com/api_keys">https://platform.deepseek.com/api_keys</a><br>
• <b>本地模型</b>: <a href="https://ollama.com">https://ollama.com</a> | <a href="https://lmstudio.ai">https://lmstudio.ai</a>
        ''')
        chat_help.setStyleSheet('''
            QTextBrowser {
                color: #666;
                font-size: 11px;
                border: 1px solid #ddd;
                border-radius: 4px;
                padding: 8px;
                background-color: #f9f9f9;
            }
        ''')
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
    
    def _on_ai_mode_changed(self):
        mode = self.ai_mode_group.checkedId()
        
        self.local_llm_group.setVisible(mode == 1)
        self.remote_api_group.setVisible(mode == 2)
        
        if mode == 0:
            self.test_result.setText('')
    
    def _on_chat_mode_changed(self):
        mode = self.chat_mode_group.checkedId()
        
        self.chat_local_llm_group.setVisible(mode == 1)
        self.chat_remote_api_group.setVisible(mode == 2)
    
    def _on_local_llm_service_changed(self, index):
        default_ports = {
            0: 'http://localhost:11434',
            1: 'http://localhost:1234',
            2: 'http://localhost:8000',
            3: 'http://localhost:7860',
            4: ''
        }
        
        if index in default_ports:
            self.local_llm_address.setText(default_ports[index])
    
    def _on_chat_local_llm_service_changed(self, index):
        default_ports = {
            0: 'http://localhost:11434',
            1: 'http://localhost:1234',
            2: 'http://localhost:8000',
            3: 'http://localhost:7860',
            4: ''
        }
        
        if index in default_ports:
            self.chat_local_llm_address.setText(default_ports[index])
    
    def _on_external_enabled_changed(self, state):
        enabled = state == Qt.Checked
        self.external_url_edit.setEnabled(enabled)
        self.external_token_edit.setEnabled(enabled)
        self.external_test_btn.setEnabled(enabled)
        self.sync_on_create.setEnabled(enabled)
        self.sync_on_complete.setEnabled(enabled)
    
    def _load_settings(self):
        ai_mode = self.config.get('ai_mode', 'local')
        mode_map = {'local': 0, 'local_llm': 1, 'remote_api': 2}
        mode_id = mode_map.get(ai_mode, 0)
        
        if mode_id == 0:
            self.local_mode_radio.setChecked(True)
        elif mode_id == 1:
            self.local_llm_mode_radio.setChecked(True)
        else:
            self.remote_api_mode_radio.setChecked(True)
        
        self.local_llm_address.setText(self.config.get('local_llm_address', 'http://localhost:11434'))
        self.local_llm_model.setText(self.config.get('local_llm_model', ''))
        
        service_map = {'ollama': 0, 'lmstudio': 1, 'vllm': 2, 'textgen': 3, 'other': 4}
        service_id = service_map.get(self.config.get('local_llm_service', 'ollama'), 0)
        self.local_llm_service_combo.setCurrentIndex(service_id)
        
        self.api_service_name.setText(self.config.get('api_service_name', ''))
        self.api_key_edit.setText(self.config.get('ai_api_key', ''))
        self.api_base_edit.setText(self.config.get('ai_api_base', ''))
        self.api_model_edit.setText(self.config.get('api_model', ''))
        
        chat_mode = self.config.get('chat_mode', 'remote_api')
        chat_mode_map = {'local_llm': 1, 'remote_api': 2}
        chat_mode_id = chat_mode_map.get(chat_mode, 2)
        
        if chat_mode_id == 1:
            self.chat_local_llm_radio.setChecked(True)
        else:
            self.chat_remote_api_radio.setChecked(True)
        
        self.chat_local_llm_address.setText(self.config.get('chat_local_llm_address', 'http://localhost:11434'))
        self.chat_local_llm_model.setText(self.config.get('chat_local_llm_model', ''))
        
        chat_service_map = {'ollama': 0, 'lmstudio': 1, 'vllm': 2, 'textgen': 3, 'other': 4}
        chat_service_id = chat_service_map.get(self.config.get('chat_local_llm_service', 'ollama'), 0)
        self.chat_local_llm_service_combo.setCurrentIndex(chat_service_id)
        
        self.chat_api_service_name.setText(self.config.get('chat_api_service_name', ''))
        self.chat_api_key_edit.setText(self.config.get('chat_api_key', ''))
        self.chat_api_base_edit.setText(self.config.get('chat_api_base', ''))
        self.chat_api_model_edit.setText(self.config.get('chat_api_model', ''))
        
        self.clipboard_check.setChecked(self.config.get('auto_detect_clipboard', True))
        
        self.external_enabled.setChecked(self.config.get('external_enabled', False))
        self.external_url_edit.setText(self.config.get('external_url', ''))
        self.external_token_edit.setText(self.config.get('external_token', ''))
        self.sync_on_create.setChecked(self.config.get('sync_on_create', True))
        self.sync_on_complete.setChecked(self.config.get('sync_on_complete', True))
        
        self.remind_enabled.setChecked(self.config.get('remind_enabled', True))
        remind_minutes = self.config.get('remind_minutes', 30)
        minute_map = {5: 0, 10: 1, 15: 2, 30: 3, 60: 4, 120: 5}
        self.remind_minutes.setCurrentIndex(minute_map.get(remind_minutes, 3))
        
        self._on_ai_mode_changed()
        self._on_chat_mode_changed()
        self._on_external_enabled_changed(Qt.Checked if self.external_enabled.isChecked() else Qt.Unchecked)
    
    def _test_local_llm(self):
        address = self.local_llm_address.text().strip()
        model = self.local_llm_model.text().strip()
        
        if not address:
            self.local_llm_test_result.setText('❌ 请输入服务地址')
            self.local_llm_test_result.setStyleSheet('color: red;')
            return
        
        if not model:
            self.local_llm_test_result.setText('❌ 请输入模型名称')
            self.local_llm_test_result.setStyleSheet('color: red;')
            return
        
        self.local_llm_test_btn.setEnabled(False)
        self.local_llm_test_result.setText('⏳ 正在测试模型...')
        self.local_llm_test_result.setStyleSheet('color: #666;')
        
        self.local_llm_test_thread = APITestThread('local_llm_model', '', address, model)
        self.local_llm_test_thread.test_finished.connect(self._on_local_llm_test_finished)
        self.local_llm_test_thread.start()
    
    def _on_local_llm_test_finished(self, success: bool, message: str):
        self.local_llm_test_btn.setEnabled(True)
        
        if success:
            self.local_llm_test_result.setText(f'✅ {message}')
            self.local_llm_test_result.setStyleSheet('color: green;')
        else:
            self.local_llm_test_result.setText(f'❌ {message}')
            self.local_llm_test_result.setStyleSheet('color: red;')
    
    def _test_api(self):
        mode = self.ai_mode_group.checkedId()
        
        if mode == 0:
            self.test_result.setText('✅ 本地模式无需测试')
            self.test_result.setStyleSheet('color: green;')
            return
        
        if mode == 1:
            address = self.local_llm_address.text().strip()
            if not address:
                self.test_result.setText('❌ 请输入服务地址')
                self.test_result.setStyleSheet('color: red;')
                return
            
            self.test_btn.setEnabled(False)
            self.test_result.setText('⏳ 正在测试连接...')
            self.test_result.setStyleSheet('color: #666;')
            
            self.test_thread = APITestThread('local_llm', '', address, self.local_llm_model.text().strip())
            self.test_thread.test_finished.connect(self._on_test_finished)
            self.test_thread.start()
        
        else:
            api_key = self.api_key_edit.text().strip()
            api_base = self.api_base_edit.text().strip()
            
            if not api_key:
                self.test_result.setText('❌ 请先输入API密钥')
                self.test_result.setStyleSheet('color: red;')
                return
            
            if not api_base:
                self.test_result.setText('❌ 请输入API地址')
                self.test_result.setStyleSheet('color: red;')
                return
            
            self.test_btn.setEnabled(False)
            self.test_result.setText('⏳ 正在测试连接...')
            self.test_result.setStyleSheet('color: #666;')
            
            self.test_thread = APITestThread(
                'remote_api', 
                api_key, 
                api_base,
                self.api_model_edit.text().strip()
            )
            self.test_thread.test_finished.connect(self._on_test_finished)
            self.test_thread.start()
    
    def _test_chat_local_llm(self):
        address = self.chat_local_llm_address.text().strip()
        model = self.chat_local_llm_model.text().strip()
        
        if not address:
            self.chat_local_llm_test_result.setText('❌ 请输入服务地址')
            self.chat_local_llm_test_result.setStyleSheet('color: red;')
            return
        
        if not model:
            self.chat_local_llm_test_result.setText('❌ 请输入模型名称')
            self.chat_local_llm_test_result.setStyleSheet('color: red;')
            return
        
        self.chat_local_llm_test_btn.setEnabled(False)
        self.chat_local_llm_test_result.setText('⏳ 正在测试模型...')
        self.chat_local_llm_test_result.setStyleSheet('color: #666;')
        
        self.chat_local_llm_test_thread = APITestThread('local_llm_model', '', address, model)
        self.chat_local_llm_test_thread.test_finished.connect(self._on_chat_local_llm_test_finished)
        self.chat_local_llm_test_thread.start()
    
    def _on_chat_local_llm_test_finished(self, success: bool, message: str):
        self.chat_local_llm_test_btn.setEnabled(True)
        
        if success:
            self.chat_local_llm_test_result.setText(f'✅ {message}')
            self.chat_local_llm_test_result.setStyleSheet('color: green;')
        else:
            self.chat_local_llm_test_result.setText(f'❌ {message}')
            self.chat_local_llm_test_result.setStyleSheet('color: red;')
    
    def _test_chat_api(self):
        mode = self.chat_mode_group.checkedId()
        
        if mode == 1:
            address = self.chat_local_llm_address.text().strip()
            if not address:
                self.chat_test_result.setText('❌ 请输入服务地址')
                self.chat_test_result.setStyleSheet('color: red;')
                return
            
            self.chat_test_btn.setEnabled(False)
            self.chat_test_result.setText('⏳ 正在测试连接...')
            self.chat_test_result.setStyleSheet('color: #666;')
            
            self.chat_test_thread = APITestThread('local_llm', '', address, self.chat_local_llm_model.text().strip())
            self.chat_test_thread.test_finished.connect(self._on_chat_test_finished)
            self.chat_test_thread.start()
        
        else:
            api_key = self.chat_api_key_edit.text().strip()
            api_base = self.chat_api_base_edit.text().strip()
            
            if not api_key:
                self.chat_test_result.setText('❌ 请先输入API密钥')
                self.chat_test_result.setStyleSheet('color: red;')
                return
            
            if not api_base:
                self.chat_test_result.setText('❌ 请输入API地址')
                self.chat_test_result.setStyleSheet('color: red;')
                return
            
            self.chat_test_btn.setEnabled(False)
            self.chat_test_result.setText('⏳ 正在测试连接...')
            self.chat_test_result.setStyleSheet('color: #666;')
            
            self.chat_test_thread = APITestThread(
                'remote_api', 
                api_key, 
                api_base,
                self.chat_api_model_edit.text().strip()
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
        mode_map = {0: 'local', 1: 'local_llm', 2: 'remote_api'}
        ai_mode = mode_map[self.ai_mode_group.checkedId()]
        self.config.set('ai_mode', ai_mode)
        
        service_map = {0: 'ollama', 1: 'lmstudio', 2: 'vllm', 3: 'textgen', 4: 'other'}
        self.config.set('local_llm_service', service_map[self.local_llm_service_combo.currentIndex()])
        self.config.set('local_llm_address', self.local_llm_address.text().strip())
        self.config.set('local_llm_model', self.local_llm_model.text().strip())
        
        self.config.set('api_service_name', self.api_service_name.text().strip())
        self.config.set('ai_api_key', self.api_key_edit.text().strip())
        self.config.set('ai_api_base', self.api_base_edit.text().strip())
        self.config.set('api_model', self.api_model_edit.text().strip())
        
        chat_mode_map = {1: 'local_llm', 2: 'remote_api'}
        chat_mode = chat_mode_map[self.chat_mode_group.checkedId()]
        self.config.set('chat_mode', chat_mode)
        
        self.config.set('chat_local_llm_service', service_map[self.chat_local_llm_service_combo.currentIndex()])
        self.config.set('chat_local_llm_address', self.chat_local_llm_address.text().strip())
        self.config.set('chat_local_llm_model', self.chat_local_llm_model.text().strip())
        
        self.config.set('chat_api_service_name', self.chat_api_service_name.text().strip())
        self.config.set('chat_api_key', self.chat_api_key_edit.text().strip())
        self.config.set('chat_api_base', self.chat_api_base_edit.text().strip())
        self.config.set('chat_api_model', self.chat_api_model_edit.text().strip())
        
        self.config.set('auto_detect_clipboard', self.clipboard_check.isChecked())
        
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
