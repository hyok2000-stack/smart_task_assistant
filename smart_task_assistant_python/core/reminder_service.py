"""
提醒服务模块 - 支持多种提醒方式
"""

import os
import platform
from datetime import datetime, timedelta
from typing import List, Dict, Any, Optional
from PyQt5.QtCore import QObject, pyqtSignal, QTimer


class ReminderService(QObject):
    reminder_triggered = pyqtSignal(dict)
    
    def __init__(self, db, config):
        super().__init__()
        
        self.db = db
        self.config = config
        self.reminded_tasks = set()
        
        self.check_timer = QTimer()
        self.check_timer.timeout.connect(self._check_reminders)
        self.check_timer.start(60000)
    
    def _check_reminders(self):
        if not self.config.get('remind_enabled', True):
            return
        
        tasks = self.db.get_all_tasks()
        now = datetime.now()
        
        for task in tasks:
            if task.get('status') in ['completed', 'cancelled']:
                continue
            
            task_id = task.get('task_id')
            deadline = task.get('deadline')
            
            if not deadline:
                continue
            
            try:
                if len(deadline) == 16:
                    deadline_dt = datetime.strptime(deadline, '%Y-%m-%d %H:%M')
                else:
                    deadline_dt = datetime.strptime(deadline, '%Y-%m-%d %H:%M:%S')
                
                reminder_times = task.get('reminder_times', '')
                if reminder_times:
                    times = [int(t.strip()) for t in reminder_times.split(',') if t.strip().isdigit()]
                else:
                    times = [self.config.get('remind_minutes', 30)]
                
                for minutes in times:
                    remind_time = deadline_dt - timedelta(minutes=minutes)
                    
                    key = f"{task_id}_{minutes}"
                    
                    if key not in self.reminded_tasks:
                        if now >= remind_time and now < deadline_dt:
                            self.reminded_tasks.add(key)
                            self._trigger_reminder(task, minutes)
                            break
            except Exception as e:
                pass
    
    def _trigger_reminder(self, task: Dict[str, Any], minutes_before: int):
        self.reminder_triggered.emit(task)
        
        if self.config.get('sound_enabled', True):
            self._play_sound()
        
        if self.config.get('popup_enabled', True):
            self._show_system_notification(task, minutes_before)
    
    def _play_sound(self):
        try:
            system = platform.system()
            if system == 'Windows':
                import winsound
                winsound.Beep(1000, 500)
                winsound.Beep(1500, 300)
            elif system == 'Darwin':
                os.system('say "任务提醒"')
            else:
                os.system('echo -e "\a"')
        except:
            pass
    
    def _show_system_notification(self, task: Dict[str, Any], minutes_before: int):
        try:
            system = platform.system()
            title = f"⏰ 任务提醒 - {task.get('title', '未知任务')}"
            message = f"距离截止还有 {minutes_before} 分钟，请及时处理！"
            
            if system == 'Windows':
                try:
                    from win10toast import ToastNotifier
                    toaster = ToastNotifier()
                    toaster.show_toast(title, message, duration=5, threaded=True)
                except ImportError:
                    self._show_windows_notification_fallback(title, message)
            elif system == 'Darwin':
                os.system(f'''osascript -e 'display notification "{message}" with title "{title}"' ''')
            else:
                try:
                    import subprocess
                    subprocess.run(['notify-send', title, message])
                except:
                    pass
        except Exception as e:
            print(f"系统通知失败: {e}")
    
    def _show_windows_notification_fallback(self, title: str, message: str):
        try:
            import ctypes
            ctypes.windll.user32.MessageBoxW(0, message, title, 0x40 | 0x1000)
        except:
            pass
    
    def clear_reminder(self, task_id: str):
        keys_to_remove = [k for k in self.reminded_tasks if k.startswith(task_id)]
        for key in keys_to_remove:
            self.reminded_tasks.remove(key)
    
    def get_upcoming_reminders(self) -> List[Dict[str, Any]]:
        tasks = self.db.get_all_tasks()
        upcoming = []
        now = datetime.now()
        
        for task in tasks:
            if task.get('status') in ['completed', 'cancelled']:
                continue
            
            deadline = task.get('deadline')
            if not deadline:
                continue
            
            try:
                if len(deadline) == 16:
                    deadline_dt = datetime.strptime(deadline, '%Y-%m-%d %H:%M')
                else:
                    deadline_dt = datetime.strptime(deadline, '%Y-%m-%d %H:%M:%S')
                
                if now < deadline_dt:
                    task['remaining_time'] = deadline_dt - now
                    upcoming.append(task)
            except:
                pass
        
        return sorted(upcoming, key=lambda x: x.get('remaining_time', timedelta.max))


class RecurringTaskManager:
    def __init__(self, db):
        self.db = db
    
    def create_recurring_task(self, base_task: Dict[str, Any], rule: str) -> List[str]:
        created_ids = []
        
        if rule == 'daily':
            for i in range(1, 8):
                new_deadline = self._calculate_next_deadline(base_task['deadline'], i, 'days')
                task_id = self._create_task_copy(base_task, new_deadline)
                created_ids.append(task_id)
        
        elif rule == 'weekly':
            for i in range(1, 5):
                new_deadline = self._calculate_next_deadline(base_task['deadline'], i * 7, 'days')
                task_id = self._create_task_copy(base_task, new_deadline)
                created_ids.append(task_id)
        
        elif rule == 'monthly':
            for i in range(1, 4):
                new_deadline = self._calculate_next_deadline(base_task['deadline'], i, 'months')
                task_id = self._create_task_copy(base_task, new_deadline)
                created_ids.append(task_id)
        
        return created_ids
    
    def _calculate_next_deadline(self, original_deadline: str, amount: int, unit: str) -> str:
        try:
            if len(original_deadline) == 16:
                dt = datetime.strptime(original_deadline, '%Y-%m-%d %H:%M')
            else:
                dt = datetime.strptime(original_deadline, '%Y-%m-%d %H:%M:%S')
            
            if unit == 'days':
                new_dt = dt + timedelta(days=amount)
            elif unit == 'months':
                month = dt.month + amount
                year = dt.year + (month - 1) // 12
                month = (month - 1) % 12 + 1
                day = min(dt.day, 28)
                new_dt = dt.replace(year=year, month=month, day=day)
            else:
                new_dt = dt
            
            return new_dt.strftime('%Y-%m-%d %H:%M:%S')
        except:
            return original_deadline
    
    def _create_task_copy(self, base_task: Dict[str, Any], new_deadline: str) -> str:
        import uuid
        
        task_id = f"T{uuid.uuid4().hex[:8].upper()}"
        now = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        
        new_task = {
            'task_id': task_id,
            'title': base_task.get('title', ''),
            'content': base_task.get('content', ''),
            'owner_name': base_task.get('owner_name', '我'),
            'deadline': new_deadline,
            'status': 'pending',
            'priority': base_task.get('priority', 'medium'),
            'acceptance_criteria': base_task.get('acceptance_criteria', ''),
            'source_type': 'recurring',
            'original_content': base_task.get('original_content', ''),
            'tags': base_task.get('tags', ''),
            'created_at': now,
            'updated_at': now,
            'is_recurring': 1,
            'recurring_rule': base_task.get('recurring_rule', ''),
            'parent_task_id': base_task.get('task_id', '')
        }
        
        self.db.insert_task(new_task)
        return task_id
    
    def handle_completed_recurring(self, task_id: str):
        task = self.db.get_task_by_id(task_id)
        if not task or not task.get('is_recurring'):
            return
        
        rule = task.get('recurring_rule', '')
        if not rule:
            return
        
        next_deadline = self._calculate_next_deadline(task['deadline'], 1, 
            'days' if rule == 'daily' else ('months' if rule == 'monthly' else 'days'))
        
        if rule == 'daily':
            next_deadline = self._calculate_next_deadline(task['deadline'], 1, 'days')
        elif rule == 'weekly':
            next_deadline = self._calculate_next_deadline(task['deadline'], 7, 'days')
        elif rule == 'monthly':
            next_deadline = self._calculate_next_deadline(task['deadline'], 1, 'months')
        
        self._create_task_copy(task, next_deadline)
