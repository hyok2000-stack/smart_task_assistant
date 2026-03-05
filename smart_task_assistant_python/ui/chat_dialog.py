"""
智答对话框 - AI对话咨询窗口（互联网化设计）
"""

from PyQt5.QtWidgets import (
    QDialog, QVBoxLayout, QHBoxLayout, QLabel, 
    QTextEdit, QPushButton, QScrollArea, QFrame, QWidget
)
from PyQt5.QtCore import Qt, QThread, pyqtSignal
from PyQt5.QtGui import QFont
import requests


class ChatMessage(QFrame):
    def __init__(self, text: str, is_user: bool = True):
        super().__init__()
        self.is_user = is_user
        self.text = text
        self._init_ui()
    
    def _init_ui(self):
        layout = QHBoxLayout(self)
        layout.setContentsMargins(12, 8, 12, 8)
        layout.setSpacing(8)
        
        if self.is_user:
            layout.addStretch()
            
            text_frame = QFrame()
            text_frame.setStyleSheet('''
                QFrame {
                    background-color: #95EC69;
                    border-radius: 8px;
                    padding: 10px 14px;
                }
            ''')
            text_layout = QVBoxLayout(text_frame)
            text_layout.setContentsMargins(0, 0, 0, 0)
            
            text_label = QLabel(self._wrap_text(self.text))
            text_label.setStyleSheet('''
                QLabel {
                    font-size: 14px;
                    color: #000;
                    line-height: 1.6;
                }
            ''')
            text_label.setWordWrap(True)
            text_label.setTextInteractionFlags(Qt.TextSelectableByMouse)
            text_layout.addWidget(text_label)
            
            layout.addWidget(text_frame)
            
            avatar = QLabel('👤')
            avatar.setStyleSheet('''
                QLabel {
                    font-size: 16px;
                    background-color: #07C160;
                    color: white;
                    border-radius: 50%;
                    padding: 6px;
                    min-width: 28px;
                    max-width: 28px;
                    min-height: 28px;
                    max-height: 28px;
                }
            ''')
            avatar.setAlignment(Qt.AlignTop)
            layout.addWidget(avatar)
        else:
            avatar = QLabel('🤖')
            avatar.setStyleSheet('''
                QLabel {
                    font-size: 16px;
                    background-color: #1890FF;
                    color: white;
                    border-radius: 50%;
                    padding: 6px;
                    min-width: 28px;
                    max-width: 28px;
                    min-height: 28px;
                    max-height: 28px;
                }
            ''')
            avatar.setAlignment(Qt.AlignTop)
            layout.addWidget(avatar)
            
            text_frame = QFrame()
            text_frame.setStyleSheet('''
                QFrame {
                    background-color: white;
                    border-radius: 8px;
                    padding: 10px 14px;
                    border: 1px solid #E8E8E8;
                }
            ''')
            text_layout = QVBoxLayout(text_frame)
            text_layout.setContentsMargins(0, 0, 0, 0)
            
            text_label = QLabel(self._wrap_text(self.text))
            text_label.setStyleSheet('''
                QLabel {
                    font-size: 14px;
                    color: #333;
                    line-height: 1.6;
                }
            ''')
            text_label.setWordWrap(True)
            text_label.setTextInteractionFlags(Qt.TextSelectableByMouse)
            text_layout.addWidget(text_label)
            
            layout.addWidget(text_frame, 1)
            layout.addStretch()
    
    def _wrap_text(self, text: str) -> str:
        if len(text) > 1000:
            return text[:1000] + '...'
        return text


class AIChatThread(QThread):
    response_ready = pyqtSignal(str)
    
    def __init__(self, config: dict, messages: list):
        super().__init__()
        self.config = config
        self.messages = messages
    
    def run(self):
        try:
            chat_mode = self.config.get('chat_mode', 'remote_api')
            
            if chat_mode == 'local_llm':
                self._call_local_llm()
            else:
                self._call_remote_api()
        except Exception as e:
            self.response_ready.emit(f"发送失败: {str(e)}")
    
    def _call_local_llm(self):
        try:
            api_base = self.config.get('chat_local_llm_address', 'http://localhost:11434')
            model = self.config.get('chat_local_llm_model', 'qwen2.5:7b')
            
            url = f'{api_base}/v1/chat/completions'
            
            response = requests.post(
                url,
                json={
                    'model': model,
                    'messages': self.messages,
                    'temperature': 0.7
                },
                timeout=60
            )
            
            if response.status_code == 200:
                result = response.json()
                content = result['choices'][0]['message']['content']
                self.response_ready.emit(content)
            else:
                self.response_ready.emit(f"本地模型服务错误: {response.status_code}")
        except requests.exceptions.ConnectionError:
            self.response_ready.emit("无法连接到本地模型服务，请确认服务已启动")
        except Exception as e:
            self.response_ready.emit(f"本地模型调用失败: {str(e)}")
    
    def _call_remote_api(self):
        try:
            api_key = self.config.get('chat_api_key', '')
            api_base = self.config.get('chat_api_base', '')
            model = self.config.get('chat_api_model', '')
            
            if not api_key:
                self.response_ready.emit("请先在设置中配置智答AI服务")
                return
            
            if not api_base:
                api_type = self.config.get('chat_api_type', '')
                if api_type == 'qwen':
                    api_base = 'https://dashscope.aliyuncs.com/compatible-mode/v1'
                    model = model or 'qwen-turbo'
                elif api_type == 'zhipu':
                    api_base = 'https://open.bigmodel.cn/api/paas/v4'
                    model = model or 'glm-4'
                elif api_type == 'openai':
                    api_base = 'https://api.openai.com/v1'
                    model = model or 'gpt-3.5-turbo'
                elif api_type == 'kimi':
                    api_base = 'https://api.moonshot.cn/v1'
                    model = model or 'moonshot-v1-8k'
                elif api_type == 'doubao':
                    api_base = 'https://ark.cn-beijing.volces.com/api/v3'
                    model = model or 'doubao-pro-32k-241215'
                else:
                    self.response_ready.emit("请先在设置中配置API地址")
                    return
            
            if not model:
                model = 'gpt-3.5-turbo'
            
            url = f'{api_base}/chat/completions'
            headers = {
                'Authorization': f'Bearer {api_key}',
                'Content-Type': 'application/json'
            }
            data = {
                'model': model,
                'messages': self.messages,
                'temperature': 0.7
            }
            
            response = requests.post(url, headers=headers, json=data, timeout=60)
            
            if response.status_code == 200:
                try:
                    result = response.json()
                    if 'choices' in result and len(result['choices']) > 0:
                        content = result['choices'][0]['message']['content']
                        self.response_ready.emit(content)
                    else:
                        self.response_ready.emit(f"API响应格式错误: {str(result)[:200]}")
                except Exception as json_error:
                    self.response_ready.emit(f"API返回数据格式错误:\n{response.text[:300]}")
            else:
                error_msg = response.text[:300] if response.text else '未知错误'
                self.response_ready.emit(f"API错误 ({response.status_code}):\n{error_msg}")
        except requests.exceptions.ConnectionError:
            self.response_ready.emit("无法连接到API服务，请检查网络或API地址")
        except requests.exceptions.Timeout:
            self.response_ready.emit("请求超时，请稍后重试")
        except Exception as e:
            self.response_ready.emit(f"API调用失败: {str(e)}")


class ChatDialog(QDialog):
    def __init__(self, parent, config):
        super().__init__(parent)
        
        self.config = config
        self.messages = []
        self.chat_thread = None
        self.thinking_widget = None
        
        self.setWindowTitle('智答助手')
        self.setMinimumSize(700, 600)
        self.resize(800, 700)
        
        self._init_ui()
    
    def _init_ui(self):
        self.setStyleSheet('''
            QDialog {
                background-color: #EDEDED;
            }
        ''')
        
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(0)
        
        header = QFrame()
        header.setFixedHeight(60)
        header.setStyleSheet('''
            QFrame {
                background-color: #EDEDED;
                border-bottom: 1px solid #D9D9D9;
            }
        ''')
        header_layout = QHBoxLayout(header)
        header_layout.setContentsMargins(20, 0, 20, 0)
        
        title_icon = QLabel('🤖')
        title_icon.setStyleSheet('font-size: 20px;')
        header_layout.addWidget(title_icon)
        
        title = QLabel('智答助手')
        title.setFont(QFont('Microsoft YaHei', 16, QFont.Bold))
        title.setStyleSheet('color: #000; margin-left: 8px;')
        header_layout.addWidget(title)
        
        header_layout.addStretch()
        
        clear_btn = QPushButton('清空对话')
        clear_btn.setCursor(Qt.PointingHandCursor)
        clear_btn.setStyleSheet('''
            QPushButton {
                background-color: transparent;
                border: none;
                color: #576B95;
                font-size: 14px;
                padding: 8px 16px;
            }
            QPushButton:hover {
                background-color: rgba(0, 0, 0, 0.05);
                border-radius: 4px;
            }
        ''')
        clear_btn.clicked.connect(self._clear_chat)
        header_layout.addWidget(clear_btn)
        
        layout.addWidget(header)
        
        chat_scroll = QScrollArea()
        chat_scroll.setStyleSheet('''
            QScrollArea {
                background-color: #EDEDED;
                border: none;
            }
            QScrollBar:vertical {
                background-color: #EDEDED;
                width: 6px;
                margin: 0px;
            }
            QScrollBar::handle:vertical {
                background-color: #C1C1C1;
                border-radius: 3px;
                min-height: 30px;
            }
            QScrollBar::handle:vertical:hover {
                background-color: #A8A8A8;
            }
            QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {
                height: 0px;
            }
        ''')
        chat_scroll.setWidgetResizable(True)
        chat_scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        
        self.chat_container = QWidget()
        self.chat_layout = QVBoxLayout(self.chat_container)
        self.chat_layout.setSpacing(12)
        self.chat_layout.setContentsMargins(16, 16, 16, 16)
        self.chat_layout.addStretch()
        
        chat_scroll.setWidget(self.chat_container)
        
        layout.addWidget(chat_scroll, 1)
        
        input_frame = QFrame()
        input_frame.setStyleSheet('''
            QFrame {
                background-color: #F7F7F7;
                border-top: 1px solid #D9D9D9;
            }
        ''')
        input_layout = QVBoxLayout(input_frame)
        input_layout.setContentsMargins(16, 12, 16, 12)
        input_layout.setSpacing(8)
        
        input_container = QHBoxLayout()
        input_container.setSpacing(8)
        
        self.input_edit = QTextEdit()
        self.input_edit.setPlaceholderText('输入您的问题...')
        self.input_edit.setFixedHeight(60)
        self.input_edit.setStyleSheet('''
            QTextEdit {
                background-color: white;
                border: 1px solid #E8E8E8;
                border-radius: 20px;
                padding: 12px 16px;
                font-size: 14px;
            }
            QTextEdit:focus {
                border-color: #1890FF;
            }
        ''')
        input_container.addWidget(self.input_edit, 1)
        
        self.send_btn = QPushButton('发送')
        self.send_btn.setCursor(Qt.PointingHandCursor)
        self.send_btn.setFixedSize(70, 40)
        self.send_btn.setStyleSheet('''
            QPushButton {
                background-color: #07C160;
                color: white;
                border: none;
                border-radius: 20px;
                font-size: 14px;
                font-weight: bold;
            }
            QPushButton:hover {
                background-color: #06AD56;
            }
            QPushButton:disabled {
                background-color: #A0A0A0;
            }
        ''')
        self.send_btn.clicked.connect(self._send_message)
        input_container.addWidget(self.send_btn)
        
        input_layout.addLayout(input_container)
        
        layout.addWidget(input_frame)
        
        self._add_welcome_message()
    
    def _add_welcome_message(self):
        welcome = "您好！我是智答助手，可以帮您解答问题、分析数据、提供建议。请问有什么可以帮您的？"
        self._add_message(welcome, False)
    
    def _add_message(self, text: str, is_user: bool):
        msg_widget = ChatMessage(text, is_user)
        self.chat_layout.insertWidget(self.chat_layout.count() - 1, msg_widget)
        
        from PyQt5.QtWidgets import QApplication
        QApplication.processEvents()
        
        try:
            scroll = self.chat_container.parent().parent()
            if scroll:
                scroll.verticalScrollBar().setValue(scroll.verticalScrollBar().maximum())
        except:
            pass
    
    def _clear_chat(self):
        for i in reversed(range(self.chat_layout.count() - 1)):
            item = self.chat_layout.itemAt(i)
            if item and item.widget():
                item.widget().deleteLater()
        
        self.messages = []
        self.thinking_widget = None
        
        from PyQt5.QtWidgets import QApplication
        QApplication.processEvents()
        
        self._add_welcome_message()
    
    def _send_message(self):
        text = self.input_edit.toPlainText().strip()
        if not text:
            return
        
        self._add_message(text, True)
        self.input_edit.clear()
        
        self.messages.append({'role': 'user', 'content': text})
        
        chat_mode = self.config.get('chat_mode', 'remote_api')
        
        if chat_mode == 'remote_api':
            api_key = self.config.get('chat_api_key', '')
            if not api_key:
                self._add_message("请先在设置中配置智答AI服务（输入API密钥和地址）", False)
                return
        
        self.send_btn.setEnabled(False)
        self.thinking_widget = ChatMessage("正在思考中...", False)
        self.chat_layout.insertWidget(self.chat_layout.count() - 1, self.thinking_widget)
        
        chat_messages = []
        for msg in self.messages:
            chat_messages.append({'role': msg['role'], 'content': msg['content']})
        
        config_dict = {
            'chat_mode': self.config.get('chat_mode', 'remote_api'),
            'chat_local_llm_address': self.config.get('chat_local_llm_address', 'http://localhost:11434'),
            'chat_local_llm_model': self.config.get('chat_local_llm_model', ''),
            'chat_api_key': self.config.get('chat_api_key', ''),
            'chat_api_base': self.config.get('chat_api_base', ''),
            'chat_api_model': self.config.get('chat_api_model', '')
        }
        
        self.chat_thread = AIChatThread(config_dict, chat_messages)
        self.chat_thread.response_ready.connect(self._on_response)
        self.chat_thread.start()
    
    def _on_response(self, response: str):
        if self.thinking_widget:
            self.thinking_widget.deleteLater()
            self.thinking_widget = None
        
        self.send_btn.setEnabled(True)
        
        self._add_message(response, False)
        self.messages.append({'role': 'assistant', 'content': response})
    
    def closeEvent(self, event):
        if self.chat_thread and self.chat_thread.isRunning():
            self.chat_thread.terminate()
            self.chat_thread.wait()
        super().closeEvent(event)
