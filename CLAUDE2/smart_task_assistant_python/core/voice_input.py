"""
语音输入模块 - 支持语音创建任务
使用sounddevice作为音频输入（PyAudio的现代替代品）
"""

import os
import wave
import tempfile
from typing import Optional


class VoiceInputService:
    def __init__(self):
        self.is_available = self._check_availability()
    
    def _check_availability(self) -> bool:
        try:
            import speech_recognition
            import sounddevice
            import numpy
            return True
        except ImportError:
            return False
    
    def listen(self, timeout: int = 5) -> Optional[str]:
        if not self.is_available:
            return None
        
        try:
            import speech_recognition as sr
            import sounddevice as sd
            import numpy as np
            
            print("正在录音...")
            
            sample_rate = 16000
            
            recording = sd.rec(
                int(timeout * sample_rate),
                samplerate=sample_rate,
                channels=1,
                dtype='int16'
            )
            sd.wait()
            
            with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as temp_file:
                temp_path = temp_file.name
                
                with wave.open(temp_path, 'wb') as wf:
                    wf.setnchannels(1)
                    wf.setsampwidth(2)
                    wf.setframerate(sample_rate)
                    wf.writeframes(recording.tobytes())
            
            recognizer = sr.Recognizer()
            
            with sr.AudioFile(temp_path) as source:
                audio = recognizer.record(source)
            
            os.unlink(temp_path)
            
            text = recognizer.recognize_google(audio, language='zh-CN')
            return text
            
        except ImportError as e:
            print(f"导入错误: {e}")
            return None
        except Exception as e:
            print(f"语音识别错误: {e}")
            return None
    
    def install_instructions(self) -> str:
        return """
要启用语音输入功能，请安装以下依赖：

pip install SpeechRecognition
pip install sounddevice
pip install numpy

注意：sounddevice是PyAudio的现代替代品，安装更简单，无需额外编译。
"""
