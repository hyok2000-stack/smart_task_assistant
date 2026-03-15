"""
日志系统模块 - 支持日志级别、文件轮转、错误追踪
"""

import os
import logging
import logging.handlers
from datetime import datetime
from typing import Optional
import traceback
import json
from pathlib import Path


class Logger:
    _instance = None
    _initialized = False
    
    def __new__(cls, *args, **kwargs):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
        return cls._instance
    
    def __init__(self, log_dir: str = None, log_level: str = 'INFO', 
                 max_bytes: int = 10 * 1024 * 1024, backup_count: int = 5):
        if self._initialized:
            return
        
        self.log_dir = log_dir or os.path.join(os.path.dirname(__file__), 'data', 'logs')
        Path(self.log_dir).mkdir(parents=True, exist_ok=True)
        
        self.log_level = getattr(logging, log_level.upper(), logging.INFO)
        self.max_bytes = max_bytes
        self.backup_count = backup_count
        
        self.logger = logging.getLogger('SmartTaskAssistant')
        self.logger.setLevel(self.log_level)
        
        self._setup_handlers()
        self._setup_error_monitor()
        
        Logger._initialized = True
    
    def _setup_handlers(self):
        formatter = logging.Formatter(
            '%(asctime)s - %(name)s - %(levelname)s - %(filename)s:%(lineno)d - %(message)s',
            datefmt='%Y-%m-%d %H:%M:%S'
        )
        
        console_handler = logging.StreamHandler()
        console_handler.setLevel(self.log_level)
        console_handler.setFormatter(formatter)
        self.logger.addHandler(console_handler)
        
        log_file = os.path.join(self.log_dir, 'app.log')
        file_handler = logging.handlers.RotatingFileHandler(
            log_file,
            maxBytes=self.max_bytes,
            backupCount=self.backup_count,
            encoding='utf-8'
        )
        file_handler.setLevel(self.log_level)
        file_handler.setFormatter(formatter)
        self.logger.addHandler(file_handler)
        
        error_log_file = os.path.join(self.log_dir, 'error.log')
        error_handler = logging.handlers.RotatingFileHandler(
            error_log_file,
            maxBytes=self.max_bytes,
            backupCount=self.backup_count,
            encoding='utf-8'
        )
        error_handler.setLevel(logging.ERROR)
        error_handler.setFormatter(formatter)
        self.logger.addHandler(error_handler)
    
    def _setup_error_monitor(self):
        self.error_file = os.path.join(self.log_dir, 'errors.json')
        if not os.path.exists(self.error_file):
            with open(self.error_file, 'w', encoding='utf-8') as f:
                json.dump([], f)
    
    def _record_error(self, error_info: dict):
        try:
            with open(self.error_file, 'r', encoding='utf-8') as f:
                errors = json.load(f)
            
            errors.append(error_info)
            
            if len(errors) > 100:
                errors = errors[-100:]
            
            with open(self.error_file, 'w', encoding='utf-8') as f:
                json.dump(errors, f, ensure_ascii=False, indent=2)
        except Exception as e:
            self.logger.error(f"Failed to record error: {e}")
    
    def debug(self, message: str, *args, **kwargs):
        self.logger.debug(message, *args, **kwargs)
    
    def info(self, message: str, *args, **kwargs):
        self.logger.info(message, *args, **kwargs)
    
    def warning(self, message: str, *args, **kwargs):
        self.logger.warning(message, *args, **kwargs)
    
    def error(self, message: str, exc_info: bool = False, *args, **kwargs):
        self.logger.error(message, exc_info=exc_info, *args, **kwargs)
        
        if exc_info:
            error_info = {
                'timestamp': datetime.now().isoformat(),
                'level': 'ERROR',
                'message': message,
                'traceback': traceback.format_exc()
            }
            self._record_error(error_info)
    
    def critical(self, message: str, exc_info: bool = True, *args, **kwargs):
        self.logger.critical(message, exc_info=exc_info, *args, **kwargs)
        
        error_info = {
            'timestamp': datetime.now().isoformat(),
            'level': 'CRITICAL',
            'message': message,
            'traceback': traceback.format_exc()
        }
        self._record_error(error_info)
    
    def exception(self, message: str, *args, **kwargs):
        self.logger.exception(message, *args, **kwargs)
        
        error_info = {
            'timestamp': datetime.now().isoformat(),
            'level': 'EXCEPTION',
            'message': message,
            'traceback': traceback.format_exc()
        }
        self._record_error(error_info)
    
    def log_performance(self, operation: str, duration: float, details: dict = None):
        perf_log = {
            'timestamp': datetime.now().isoformat(),
            'operation': operation,
            'duration_ms': round(duration * 1000, 2),
            'details': details or {}
        }
        
        perf_file = os.path.join(self.log_dir, 'performance.log')
        with open(perf_file, 'a', encoding='utf-8') as f:
            f.write(json.dumps(perf_log, ensure_ascii=False) + '\n')
        
        if duration > 1.0:
            self.warning(f"Slow operation detected: {operation} took {duration:.2f}s")
    
    def log_user_action(self, action: str, details: dict = None):
        action_log = {
            'timestamp': datetime.now().isoformat(),
            'action': action,
            'details': details or {}
        }
        
        action_file = os.path.join(self.log_dir, 'user_actions.log')
        with open(action_file, 'a', encoding='utf-8') as f:
            f.write(json.dumps(action_log, ensure_ascii=False) + '\n')
    
    def get_recent_errors(self, limit: int = 10) -> list:
        try:
            with open(self.error_file, 'r', encoding='utf-8') as f:
                errors = json.load(f)
            return errors[-limit:]
        except:
            return []
    
    def clear_old_logs(self, days: int = 30):
        cutoff = datetime.now().timestamp() - (days * 24 * 60 * 60)
        
        for filename in os.listdir(self.log_dir):
            filepath = os.path.join(self.log_dir, filename)
            if os.path.isfile(filepath):
                if os.path.getmtime(filepath) < cutoff:
                    try:
                        os.remove(filepath)
                        self.info(f"Removed old log file: {filename}")
                    except Exception as e:
                        self.error(f"Failed to remove old log file {filename}: {e}")


def performance_monitor(func):
    import time
    from functools import wraps
    
    @wraps(func)
    def wrapper(*args, **kwargs):
        logger = Logger()
        start_time = time.time()
        
        try:
            result = func(*args, **kwargs)
            duration = time.time() - start_time
            logger.log_performance(func.__name__, duration)
            return result
        except Exception as e:
            duration = time.time() - start_time
            logger.log_performance(func.__name__, duration, {'error': str(e)})
            logger.exception(f"Exception in {func.__name__}")
            raise
    
    return wrapper


def async_performance_monitor(func):
    import time
    import asyncio
    from functools import wraps
    
    @wraps(func)
    async def wrapper(*args, **kwargs):
        logger = Logger()
        start_time = time.time()
        
        try:
            result = await func(*args, **kwargs)
            duration = time.time() - start_time
            logger.log_performance(func.__name__, duration)
            return result
        except Exception as e:
            duration = time.time() - start_time
            logger.log_performance(func.__name__, duration, {'error': str(e)})
            logger.exception(f"Exception in {func.__name__}")
            raise
    
    return wrapper


logger = Logger()
