"""
任务识别服务模块 - 集成AI服务
"""

from datetime import datetime
from typing import Dict, Any
from .ai_service import AIService

class TaskRecognitionService:
    def __init__(self, config: Dict[str, Any] = None):
        self.config = config or {}
        self.ai_service = AIService(self.config)
    
    def configure(self, config: Dict[str, Any]):
        self.config = config
        self.ai_service = AIService(config)
    
    def recognize(self, text: str) -> Dict[str, Any]:
        return self.ai_service.recognize_task(text)
    
    def format_task_for_copy(self, task: Dict[str, Any]) -> str:
        lines = []
        lines.append(f"【任务标题】{task['title']}")
        lines.append(f"【负责人】{task.get('owner_name', '我')}")
        lines.append(f"【截止时间】{task['deadline']}")
        lines.append(f"【任务内容】")
        lines.append(task.get('content', ''))
        lines.append(f"【验收标准】{task.get('acceptance_criteria', '')}")
        
        return '\n'.join(lines)
