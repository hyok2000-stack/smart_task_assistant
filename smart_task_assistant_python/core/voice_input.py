"""
语音输入模块 - 支持语音创建任务
"""

import os
import platform
from typing import Optional


class VoiceInputService:
    def __init__(self):
        self.is_available = self._check_availability()
    
    def _check_availability(self) -> bool:
        try:
            import speech_recognition
            return True
        except ImportError:
            return False
    
    def listen(self, timeout: int = 5) -> Optional[str]:
        if not self.is_available:
            return None
        
        try:
            import speech_recognition as sr
            
            recognizer = sr.Recognizer()
            
            with sr.Microphone() as source:
                recognizer.adjust_for_ambient_noise(source, duration=1)
                audio = recognizer.listen(source, timeout=timeout)
            
            text = recognizer.recognize_google(audio, language='zh-CN')
            return text
            
        except ImportError:
            return None
        except Exception as e:
            print(f"语音识别错误: {e}")
            return None
    
    def install_instructions(self) -> str:
        return """
要启用语音输入功能，请安装以下依赖：

pip install SpeechRecognition
pip install pyaudio

Windows用户可能需要：
pip install pipwin
pipwin install pyaudio
"""
