"""
错误监控模块 - 异常捕获、错误报告、错误恢复
"""

import sys
import traceback
import json
from datetime import datetime
from typing import Optional, Dict, Any, Callable
from functools import wraps
from core.logger import logger


class ErrorMonitor:
    def __init__(self):
        self.error_handlers = {}
        self.error_count = {}
        self.critical_errors = []
        self._setup_global_handler()
    
    def _setup_global_handler(self):
        def exception_hook(exc_type, exc_value, exc_traceback):
            error_info = {
                'timestamp': datetime.now().isoformat(),
                'type': exc_type.__name__,
                'value': str(exc_value),
                'traceback': ''.join(traceback.format_exception(exc_type, exc_value, exc_traceback))
            }
            
            logger.critical(f"Unhandled exception: {exc_type.__name__}: {exc_value}")
            
            self.critical_errors.append(error_info)
            if len(self.critical_errors) > 50:
                self.critical_errors = self.critical_errors[-50:]
            
            self._save_critical_error(error_info)
            
            sys.__excepthook__(exc_type, exc_value, exc_traceback)
        
        sys.excepthook = exception_hook
    
    def _save_critical_error(self, error_info: dict):
        try:
            error_file = logger.log_dir + '/critical_errors.json'
            errors = []
            
            import os
            if os.path.exists(error_file):
                with open(error_file, 'r', encoding='utf-8') as f:
                    errors = json.load(f)
            
            errors.append(error_info)
            
            if len(errors) > 100:
                errors = errors[-100:]
            
            with open(error_file, 'w', encoding='utf-8') as f:
                json.dump(errors, f, ensure_ascii=False, indent=2)
        except Exception as e:
            logger.error(f"Failed to save critical error: {e}")
    
    def register_handler(self, error_type: type, handler: Callable):
        self.error_handlers[error_type] = handler
    
    def handle_error(self, error: Exception, context: Dict[str, Any] = None) -> bool:
        error_type = type(error)
        
        error_key = f"{error_type.__name__}_{context.get('operation', 'unknown') if context else 'unknown'}"
        self.error_count[error_key] = self.error_count.get(error_key, 0) + 1
        
        if self.error_count[error_key] > 10:
            logger.warning(f"Error {error_key} occurred {self.error_count[error_key]} times, suppressing further logs")
            return False
        
        logger.exception(f"Error occurred: {error}")
        
        if error_type in self.error_handlers:
            try:
                return self.error_handlers[error_type](error, context)
            except Exception as handler_error:
                logger.error(f"Error handler failed: {handler_error}")
                return False
        
        return False
    
    def get_error_stats(self) -> Dict[str, Any]:
        return {
            'error_count': dict(self.error_count),
            'critical_errors_count': len(self.critical_errors),
            'recent_critical_errors': self.critical_errors[-5:]
        }
    
    def reset_error_count(self, error_key: str = None):
        if error_key:
            self.error_count.pop(error_key, None)
        else:
            self.error_count.clear()


error_monitor = ErrorMonitor()


def catch_errors(default_return=None, reraise: bool = False):
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            try:
                return func(*args, **kwargs)
            except Exception as e:
                context = {
                    'function': func.__name__,
                    'operation': func.__name__
                }
                
                handled = error_monitor.handle_error(e, context)
                
                if not handled and reraise:
                    raise
                
                return default_return
        
        return wrapper
    return decorator


def catch_async_errors(default_return=None, reraise: bool = False):
    def decorator(func):
        @wraps(func)
        async def wrapper(*args, **kwargs):
            try:
                return await func(*args, **kwargs)
            except Exception as e:
                context = {
                    'function': func.__name__,
                    'operation': func.__name__
                }
                
                handled = error_monitor.handle_error(e, context)
                
                if not handled and reraise:
                    raise
                
                return default_return
        
        return wrapper
    return decorator


class ErrorRecovery:
    def __init__(self):
        self.recovery_strategies = {}
    
    def register_strategy(self, error_type: type, strategy: Callable):
        self.recovery_strategies[error_type] = strategy
    
    def attempt_recovery(self, error: Exception, context: Dict[str, Any] = None) -> Any:
        error_type = type(error)
        
        if error_type in self.recovery_strategies:
            try:
                logger.info(f"Attempting recovery for {error_type.__name__}")
                result = self.recovery_strategies[error_type](error, context)
                logger.info(f"Recovery successful for {error_type.__name__}")
                return result
            except Exception as recovery_error:
                logger.error(f"Recovery failed for {error_type.__name__}: {recovery_error}")
                raise error
        
        raise error


error_recovery = ErrorRecovery()


def retry_on_error(max_retries: int = 3, delay: float = 1.0, backoff: float = 2.0):
    import time
    
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            retries = 0
            current_delay = delay
            
            while retries < max_retries:
                try:
                    return func(*args, **kwargs)
                except Exception as e:
                    retries += 1
                    
                    if retries >= max_retries:
                        logger.error(f"Function {func.__name__} failed after {max_retries} retries")
                        raise
                    
                    logger.warning(
                        f"Function {func.__name__} failed (attempt {retries}/{max_retries}), "
                        f"retrying in {current_delay}s: {e}"
                    )
                    
                    time.sleep(current_delay)
                    current_delay *= backoff
        
        return wrapper
    return decorator


class SafeContext:
    def __init__(self, operation_name: str, default_return: Any = None):
        self.operation_name = operation_name
        self.default_return = default_return
        self.start_time = None
    
    def __enter__(self):
        import time
        self.start_time = time.time()
        logger.debug(f"Starting operation: {self.operation_name}")
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        import time
        duration = time.time() - self.start_time
        
        if exc_type is not None:
            logger.error(
                f"Operation {self.operation_name} failed after {duration:.2f}s: {exc_val}",
                exc_info=True
            )
            
            error_monitor.handle_error(exc_val, {'operation': self.operation_name})
            
            return True
        else:
            logger.debug(f"Operation {self.operation_name} completed in {duration:.2f}s")
            return False
    
    def get_result(self, result: Any = None) -> Any:
        return result if result is not None else self.default_return
