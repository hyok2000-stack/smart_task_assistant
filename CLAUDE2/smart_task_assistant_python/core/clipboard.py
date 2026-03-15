"""
剪贴板监听服务模块
"""

import time
import threading
import re
from typing import Callable, Optional
from PyQt5.QtCore import QObject, pyqtSignal

class ClipboardService(QObject):
    clipboard_detected = pyqtSignal(str)
    
    def __init__(self):
        super().__init__()
        self._monitoring = False
        self._thread: Optional[threading.Thread] = None
        self._last_content: str = ''
        self._interval: float = 2.0
        
        self._task_keywords = [
            '完成', '提交', '发送', '回复', '确认', '审核', '审批',
            '整理', '汇总', '总结', '编写', '准备', '安排', '开会',
            '明天', '后天', '下周', '今天', '本周', '月底',
            '之前', '截止', '期限',
            '@', '负责', '交给', '通知', '提醒',
        ]
    
    def start_monitoring(self, interval: float = 2.0):
        if self._monitoring:
            return
        
        self._interval = interval
        self._monitoring = True
        self._thread = threading.Thread(target=self._monitor_loop, daemon=True)
        self._thread.start()
    
    def stop_monitoring(self):
        self._monitoring = False
        if self._thread:
            self._thread.join(timeout=1.0)
            self._thread = None
    
    def _monitor_loop(self):
        import pyperclip
        
        while self._monitoring:
            try:
                content = pyperclip.paste()
                
                if content and content != self._last_content:
                    if self._is_valid_task_content(content):
                        self._last_content = content
                        self.clipboard_detected.emit(content)
            except Exception:
                pass
            
            time.sleep(self._interval)
    
    def _is_valid_task_content(self, content: str) -> bool:
        if not content or len(content) < 4:
            return False
        
        if len(content) > 2000:
            return False
        
        url_pattern = r'https?://[^\s]+'
        if re.search(url_pattern, content) and len(content) < 50:
            return False
        
        for keyword in self._task_keywords:
            if keyword in content:
                return True
        
        if re.search(r'[。！？\n]', content):
            return True
        
        return False
    
    def get_current_content(self) -> str:
        try:
            import pyperclip
            return pyperclip.paste()
        except:
            return ''
    
    def copy_to_clipboard(self, text: str):
        try:
            import pyperclip
            pyperclip.copy(text)
            self._last_content = text
        except:
            pass
    
    @property
    def is_monitoring(self) -> bool:
        return self._monitoring
