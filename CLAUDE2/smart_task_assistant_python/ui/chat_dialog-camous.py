"""
智答对话框 - AI对话咨询窗口
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
        if self.is_user:
            self.setStyleSheet('''
                QFrame {
                    background-color: #E3F2FD;
                    border-radius: 12px;
                    padding: 12px 16px;
                    margin: 4px 0px;
                }
            ''')
            layout = QHBoxLayout(self)
            
            avatar = QLabel('👤')
            avatar.setStyleSheet('''
                QLabel {
                    font-size: 24px;
                    background-color: #2196F3;
                    color: white;
                    border-radius: 50%;
                    padding: 8px;
                    min-width: 36px;
                    max-width: 36px;
                }
            ''')
            layout.addWidget(avatar)
            
            text_label = QLabel(self._wrap_text(self.text))
            text_label.setStyleSheet('''
                QLabel {
                    font-size: 14px;
                    line-height: 1.5;
                }
            ''')
            text_label.setWordWrap(True)
            layout.addWidget(text_label, 1)
        else:
            self.setStyleSheet('''
                QFrame {
                    background-color: #F5F5F5;
                    border-radius: 12px;
                    padding: 12px 16px;
                    margin: 4px 1px;
                }
            ''')
            layout = QHBoxLayout(self)
            layout.addStretch()
            
            avatar = QLabel('🤖')
            avatar.setStyleSheet('''
                QLabel {
                    font-size: 24px;
                    background-color: #9C27B0;
                    color: white;
                    border-radius: 50%;
                    padding: 8px;
                    min-width: 36px;
                    max-width: 36px;
                }
            ''')
            layout.addWidget(avatar)
            
            text_label = QLabel(self._wrap_text(self.text))
            text_label.setStyleSheet('''
                QLabel {
                    font-size: 14px;
                    line-height: 1.5;
                    color: #333;
                }
            ''')
            text_label.setWordWrap(True)
            layout.addWidget(text_label, 1)
    
    def _wrap_text(self, text: str) -> str:
        if len(text) > 500:
            return text[:500] + '...'
        return text


class AIChatThread(QThread):
    response_ready = pyqtSignal(str)
    
    def __init__(self, api_type: str, api_key: str, api_base: str, messages: list):
        super().__init__()
        self.api_type = api_type
        self.api_key = api_key
        self.api_base = api_base
        self.messages = messages
    
    def run(self):
        try:
            if self.api_type == 'doubao':
                self._call_doubao()
            elif self.api_type == 'kimi':
                self._call_kimi()
            elif self.api_type == 'openai':
                self._call_openai()
            elif self.api_type == 'qwen':
                self._call_qwen()
            elif self.api_type == 'zhipu':
                self._call_zhipu()
            else:
                self.response_ready.emit("请先在设置中配置AI服务")
        except Exception as e:
            self.response_ready.emit(f"发送失败: {str(e)}")
    
    def _call_openai(self):
        url = f'{self.api_base or "https://api.openai.com/v1"}/chat/completions'
        headers = {
            'Authorization': f'Bearer {self.api_key}',
            'Content-Type': 'application/json'
        }
        data = {
            'model': 'gpt-3.5-turbo',
            'messages': self.messages,
            'temperature': 0.7
        }
        response = requests.post(url, headers=headers, json=data, timeout=60)
        if response.status_code == 200:
            result = response.json()
            content = result['choices'][0]['message']['content']
            self.response_ready.emit(content)
        else:
            self.response_ready.emit(f"API错误: {response.status_code}")
    
    def _call_qwen(self):
        url = 'https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation'
        headers = {
            'Authorization': f'Bearer {self.api_key}',
            'Content-Type': 'application/json'
        }
        data = {
            'model': 'qwen-turbo',
            'input': {'messages': self.messages},
            'parameters': {'temperature': 0.7, 'result_format': 'message'}
        }
        response = requests.post(url, headers=headers, json=data, timeout=60)
        if response.status_code == 200:
            result = response.json()
            if 'output' in result and 'choices' in result['output']:
                content = result['output']['choices'][0]['message']['content']
                self.response_ready.emit(content)
            else:
                self.response_ready.emit(f"API响应格式错误")
        else:
            self.response_ready.emit(f"API错误: {response.status_code}")
    
    def _call_zhipu(self):
        url = 'https://open.bigmodel.cn/api/paas/v4/chat/completions'
        headers = {
            'Authorization': f'Bearer {self.api_key}',
            'Content-Type': 'application/json'
        }
        data = {
            'model': 'glm-4-flash',
            'messages': self.messages,
            'temperature': 0.7
        }
        response = requests.post(url, headers=headers, json=data, timeout=60)
        if response.status_code == 200:
            result = response.json()
            content = result['choices'][0]['message']['content']
            self.response_ready.emit(content)
        else:
            self.response_ready.emit(f"API错误: {response.status_code}")
    
    def _call_doubao(self):
        url = f'{self.api_base or "https://ark.cn-beijing.volces.com/api/v3"}/chat/completions'
        headers = {
            'Authorization': f'Bearer {self.api_key}',
            'Content-Type': 'application/json'
        }
        data = {
            'model': 'doubao-pro-32k-241215',
            'messages': self.messages,
            'temperature': 0.7
        }
        response = requests.post(url, headers=headers, json=data, timeout=60)
        if response.status_code == 200:
            result = response.json()
            content = result['choices'][0]['message']['content']
            self.response_ready.emit(content)
        else:
            self.response_ready.emit(f"API错误: {response.status_code} - {response.text[:200]}")
    
    def _call_kimi(self):
        url = f'{self.api_base or "https://api.moonshot.cn/v1"}/chat/completions'
        headers = {
            'Authorization': f'Bearer {self.api_key}',
            'Content-Type': 'application/json'
        }
        data = {
            'model': 'moonshot-v1-8k',
            'messages': self.messages,
            'temperature': 0.7
        }
        response = requests.post(url, headers=headers, json=data, timeout=60)
        if response.status_code == 200:
            result = response.json()
            content = result['choices'][0]['message']['content']
            self.response_ready.emit(content)
        else:
            self.response_ready.emit(f"API错误: {response.status_code} - {response.text[:200]}")


class ChatDialog(QDialog):
    def __init__(self, parent, config):
        super().__init__(parent)
        
        self.config = config
        self.messages = []
        self.chat_thread = None
        self.thinking_widget = None
        
        self.setWindowTitle('🤖 智答助手')
        self.setMinimumSize(700, 600)
        self.resize(800, 700)
        
        self._init_ui()
    
    def _init_ui(self):
        self.setStyleSheet('''
            QDialog {
                background-color: #f5f5f5;
            }
        ''')
        
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(0)
        
        header = QFrame()
        header.setStyleSheet('''
            QFrame {
                background-color: white;
                border-bottom: 1px solid #E0E0E0;
                padding: 16px 20px;
            }
        ''')
        header_layout = QHBoxLayout(header)
        
        title = QLabel('🤖 智答助手')
        title.setFont(QFont('Microsoft YaHei', 18, QFont.Bold))
        title.setStyleSheet('color: #1976D2;')
        header_layout.addWidget(title)
        
        header_layout.addStretch()
        
        clear_btn = QPushButton('清空对话')
        clear_btn.setStyleSheet('''
            QPushButton {
                background-color: #f5f5f5;
                border: 1px solid #ddd;
                padding: 6px 16px;
                border-radius: 4px;
            }
            QPushButton:hover {
                background-color: #e0e0e0;
            }
        ''')
        clear_btn.clicked.connect(self._clear_chat)
        header_layout.addWidget(clear_btn)
        
        close_btn = QPushButton('✕')
        close_btn.setStyleSheet('''
            QPushButton {
                background-color: #f5f5f5;
                border: none;
                font-size: 18px;
                padding: 4px 8px;
            }
            QPushButton:hover {
                background-color: #e0e0e0;
            }
        ''')
        close_btn.clicked.connect(self.close)
        header_layout.addWidget(close_btn)
        
        layout.addWidget(header)
        
        chat_scroll = QScrollArea()
        chat_scroll.setStyleSheet('''
            QScrollArea {
                background-color: white;
                border: none;
            }
        ''')
        chat_scroll.setWidgetResizable(True)
        
        self.chat_container = QWidget()
        self.chat_layout = QVBoxLayout(self.chat_container)
        self.chat_layout.setSpacing(8)
        self.chat_layout.setContentsMargins(16, 16, 16, 16)
        self.chat_layout.addStretch()
        
        chat_scroll.setWidget(self.chat_container)
        
        layout.addWidget(chat_scroll, 1)
        
        input_frame = QFrame()
        input_frame.setStyleSheet('''
            QFrame {
                background-color: white;
                border-top: 1px solid #E0E0E0;
                padding: 12px 16px;
            }
        ''')
        input_layout = QHBoxLayout(input_frame)
        input_layout.setSpacing(12)
        
        self.input_edit = QTextEdit()
        self.input_edit.setPlaceholderText('输入您的问题...')
        self.input_edit.setStyleSheet('''
            QTextEdit {
                border: 1px solid #ddd;
                border-radius: 8px;
                padding: 8px 12px;
                font-size: 14px;
                max-height: 100px;
            }
            QTextEdit:focus {
                border-color: #2196F3;
            }
        ''')
        input_layout.addWidget(self.input_edit, 1)
        
        self.send_btn = QPushButton('发送')
        self.send_btn.setStyleSheet('''
            QPushButton {
                background-color: #2196F3;
                color: white;
                border: none;
                padding: 10px 24px;
                border-radius: 8px;
                font-weight: bold;
            }
            QPushButton:hover {
                background-color: #1976D2;
            }
            QPushButton:disabled {
                background-color: #ccc;
            }
        ''')
        self.send_btn.clicked.connect(self._send_message)
        input_layout.addWidget(self.send_btn)
        
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
        
        api_type = self.config.get('chat_api_type', 'qwen')
        api_key = self.config.get('chat_api_key', '')
        api_base = self.config.get('chat_api_base', '')
        
        if not api_key:
            self._add_message("请先在设置中配置智答AI服务（选择OpenAI、通义千问或智谱AI并输入API密钥）", False)
            return
        
        self.send_btn.setEnabled(False)
        self.thinking_widget = ChatMessage("正在思考中...", False)
        self.chat_layout.insertWidget(self.chat_layout.count() - 1, self.thinking_widget)
        
        chat_messages = []
        for msg in self.messages:
            chat_messages.append({'role': msg['role'], 'content': msg['content']})
        
        self.chat_thread = AIChatThread(api_type, api_key, api_base, chat_messages)
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
