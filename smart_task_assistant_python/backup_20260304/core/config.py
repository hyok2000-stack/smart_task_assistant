"""
配置管理模块
"""

import os
import json
from datetime import datetime

class Config:
    def __init__(self):
        self.app_dir = os.path.dirname(os.path.abspath(__file__))
        self.data_dir = os.path.join(self.app_dir, 'data')
        self.config_file = os.path.join(self.data_dir, 'config.json')
        
        os.makedirs(self.data_dir, exist_ok=True)
        
        self.db_path = os.path.join(self.data_dir, 'tasks.db')
        self.log_file = os.path.join(self.data_dir, 'app.log')
        
        self.default_settings = {
            'auto_detect_clipboard': True,
            'auto_generate_acceptance': True,
            'default_deadline': 'same_day',
            'reminder_advance_minutes': 60,
            'theme': 'light',
            'language': 'zh_CN'
        }
        
        self.settings = self._load_settings()
    
    def _load_settings(self):
        if os.path.exists(self.config_file):
            try:
                with open(self.config_file, 'r', encoding='utf-8') as f:
                    saved = json.load(f)
                    return {**self.default_settings, **saved}
            except:
                return self.default_settings.copy()
        return self.default_settings.copy()
    
    def save_settings(self):
        with open(self.config_file, 'w', encoding='utf-8') as f:
            json.dump(self.settings, f, ensure_ascii=False, indent=2)
    
    def get(self, key, default=None):
        return self.settings.get(key, default)
    
    def set(self, key, value):
        self.settings[key] = value
        self.save_settings()
