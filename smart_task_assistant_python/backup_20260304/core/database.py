"""
数据库管理模块
"""

import sqlite3
import os
from datetime import datetime, timedelta
from typing import List, Optional, Dict, Any

class DatabaseManager:
    def __init__(self, db_path: str):
        self.db_path = db_path
        self.conn = None
    
    def get_connection(self):
        if self.conn is None:
            self.conn = sqlite3.connect(self.db_path)
            self.conn.row_factory = sqlite3.Row
        return self.conn
    
    def init_database(self):
        conn = self.get_connection()
        cursor = conn.cursor()
        
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS tasks (
                task_id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                content TEXT,
                owner_name TEXT DEFAULT '我',
                deadline TEXT NOT NULL,
                status TEXT DEFAULT 'pending',
                priority TEXT DEFAULT 'medium',
                acceptance_criteria TEXT,
                source_type TEXT DEFAULT 'manual',
                original_content TEXT,
                tags TEXT,
                reminder TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                completed_at TEXT
            )
        ''')
        
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS templates (
                template_id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                default_title TEXT,
                default_content TEXT,
                default_deadline_rule TEXT,
                default_acceptance TEXT,
                created_at TEXT NOT NULL
            )
        ''')
        
        cursor.execute('''
            CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status)
        ''')
        
        cursor.execute('''
            CREATE INDEX IF NOT EXISTS idx_tasks_deadline ON tasks(deadline)
        ''')
        
        conn.commit()
    
    def insert_task(self, task: Dict[str, Any]) -> str:
        conn = self.get_connection()
        cursor = conn.cursor()
        
        cursor.execute('''
            INSERT INTO tasks (
                task_id, title, content, owner_name, deadline, status, priority,
                acceptance_criteria, source_type, original_content, tags, reminder,
                created_at, updated_at, completed_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            task['task_id'], task['title'], task.get('content', ''),
            task.get('owner_name', '我'), task['deadline'],
            task.get('status', 'pending'), task.get('priority', 'medium'),
            task.get('acceptance_criteria', ''), task.get('source_type', 'manual'),
            task.get('original_content', ''), task.get('tags', ''),
            task.get('reminder'), task['created_at'], task['updated_at'],
            task.get('completed_at')
        ))
        
        conn.commit()
        return task['task_id']
    
    def get_all_tasks(self) -> List[Dict[str, Any]]:
        conn = self.get_connection()
        cursor = conn.cursor()
        
        cursor.execute('SELECT * FROM tasks ORDER BY created_at DESC')
        rows = cursor.fetchall()
        
        return [dict(row) for row in rows]
    
    def get_task_by_id(self, task_id: str) -> Optional[Dict[str, Any]]:
        conn = self.get_connection()
        cursor = conn.cursor()
        
        cursor.execute('SELECT * FROM tasks WHERE task_id = ?', (task_id,))
        row = cursor.fetchone()
        
        return dict(row) if row else None
    
    def get_tasks_by_status(self, status: str) -> List[Dict[str, Any]]:
        conn = self.get_connection()
        cursor = conn.cursor()
        
        cursor.execute(
            'SELECT * FROM tasks WHERE status = ? ORDER BY created_at DESC',
            (status,)
        )
        rows = cursor.fetchall()
        
        return [dict(row) for row in rows]
    
    def get_today_tasks(self) -> List[Dict[str, Any]]:
        conn = self.get_connection()
        cursor = conn.cursor()
        
        today = datetime.now().strftime('%Y-%m-%d')
        
        cursor.execute('''
            SELECT * FROM tasks 
            WHERE date(deadline) = ? 
            AND status NOT IN ('completed', 'cancelled')
            ORDER BY created_at DESC
        ''', (today,))
        rows = cursor.fetchall()
        
        return [dict(row) for row in rows]
    
    def get_overdue_tasks(self) -> List[Dict[str, Any]]:
        conn = self.get_connection()
        cursor = conn.cursor()
        
        now = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        
        cursor.execute('''
            SELECT * FROM tasks 
            WHERE (
                (LENGTH(deadline) = 16 AND deadline || ':00' < ?) OR
                (LENGTH(deadline) > 16 AND deadline < ?)
            )
            AND status NOT IN ('completed', 'cancelled')
            ORDER BY created_at DESC
        ''', (now, now))
        rows = cursor.fetchall()
        
        return [dict(row) for row in rows]
    
    def get_tasks_by_filters(self, priority: str = '', owner: str = '', 
                             time_filter: str = '', title: str = '', content: str = '') -> List[Dict[str, Any]]:
        conn = self.get_connection()
        cursor = conn.cursor()
        
        query = 'SELECT * FROM tasks WHERE 1=1'
        params = []
        
        if priority:
            query += ' AND priority = ?'
            params.append(priority)
        
        if owner:
            query += ' AND owner_name LIKE ?'
            params.append(f'%{owner}%')
        
        if title:
            query += ' AND title LIKE ?'
            params.append(f'%{title}%')
        
        if content:
            query += ' AND content LIKE ?'
            params.append(f'%{content}%')
        
        now = datetime.now()
        
        if time_filter == 'today':
            today = now.strftime('%Y-%m-%d')
            query += ' AND date(deadline) = ?'
            params.append(today)
        elif time_filter == 'tomorrow':
            tomorrow = (now + timedelta(days=1)).strftime('%Y-%m-%d')
            query += ' AND date(deadline) = ?'
            params.append(tomorrow)
        elif time_filter == 'this_week':
            start_of_week = now - timedelta(days=now.weekday())
            end_of_week = start_of_week + timedelta(days=6)
            query += ' AND date(deadline) BETWEEN ? AND ?'
            params.extend([start_of_week.strftime('%Y-%m-%d'), end_of_week.strftime('%Y-%m-%d')])
        elif time_filter == 'this_month':
            start_of_month = now.replace(day=1)
            if now.month == 12:
                end_of_month = now.replace(year=now.year + 1, month=1, day=1) - timedelta(days=1)
            else:
                end_of_month = now.replace(month=now.month + 1, day=1) - timedelta(days=1)
            query += ' AND date(deadline) BETWEEN ? AND ?'
            params.extend([start_of_month.strftime('%Y-%m-%d'), end_of_month.strftime('%Y-%m-%d')])
        elif time_filter == 'overdue':
            now_str = now.strftime('%Y-%m-%d %H:%M:%S')
            query += ' AND deadline < ? AND status NOT IN (?, ?)'
            params.extend([now_str, 'completed', 'cancelled'])
        
        query += ' ORDER BY created_at DESC'
        
        cursor.execute(query, params)
        rows = cursor.fetchall()
        
        return [dict(row) for row in rows]
    
    def update_task(self, task_id: str, updates: Dict[str, Any]) -> bool:
        conn = self.get_connection()
        cursor = conn.cursor()
        
        updates['updated_at'] = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        
        set_clause = ', '.join([f'{k} = ?' for k in updates.keys()])
        values = list(updates.values()) + [task_id]
        
        cursor.execute(
            f'UPDATE tasks SET {set_clause} WHERE task_id = ?',
            values
        )
        
        conn.commit()
        return cursor.rowcount > 0
    
    def update_task_status(self, task_id: str, status: str) -> bool:
        updates = {'status': status}
        if status == 'completed':
            updates['completed_at'] = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        return self.update_task(task_id, updates)
    
    def delete_task(self, task_id: str) -> bool:
        conn = self.get_connection()
        cursor = conn.cursor()
        
        cursor.execute('DELETE FROM tasks WHERE task_id = ?', (task_id,))
        conn.commit()
        
        return cursor.rowcount > 0
    
    def get_task_stats(self) -> Dict[str, int]:
        conn = self.get_connection()
        cursor = conn.cursor()
        
        stats = {}
        
        cursor.execute("SELECT COUNT(*) FROM tasks")
        stats['total'] = cursor.fetchone()[0]
        
        cursor.execute("SELECT COUNT(*) FROM tasks WHERE status = 'pending'")
        stats['pending'] = cursor.fetchone()[0]
        
        cursor.execute("SELECT COUNT(*) FROM tasks WHERE status = 'in_progress'")
        stats['in_progress'] = cursor.fetchone()[0]
        
        cursor.execute("SELECT COUNT(*) FROM tasks WHERE status = 'completed'")
        stats['completed'] = cursor.fetchone()[0]
        
        now = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        cursor.execute('''
            SELECT COUNT(*) FROM tasks 
            WHERE (
                (LENGTH(deadline) = 16 AND deadline || ':00' < ?) OR
                (LENGTH(deadline) > 16 AND deadline < ?)
            )
            AND status NOT IN ('completed', 'cancelled')
        ''', (now, now))
        stats['overdue'] = cursor.fetchone()[0]
        
        return stats
    
    def insert_template(self, template: Dict[str, Any]) -> str:
        conn = self.get_connection()
        cursor = conn.cursor()
        
        cursor.execute('''
            INSERT INTO templates (
                template_id, name, default_title, default_content,
                default_deadline_rule, default_acceptance, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
        ''', (
            template['template_id'], template['name'],
            template.get('default_title', ''), template.get('default_content', ''),
            template.get('default_deadline_rule', 'same_day'),
            template.get('default_acceptance', ''), template['created_at']
        ))
        
        conn.commit()
        return template['template_id']
    
    def get_all_templates(self) -> List[Dict[str, Any]]:
        conn = self.get_connection()
        cursor = conn.cursor()
        
        cursor.execute('SELECT * FROM templates ORDER BY name ASC')
        rows = cursor.fetchall()
        
        return [dict(row) for row in rows]
    
    def delete_template(self, template_id: str) -> bool:
        conn = self.get_connection()
        cursor = conn.cursor()
        
        cursor.execute('DELETE FROM templates WHERE template_id = ?', (template_id,))
        conn.commit()
        
        return cursor.rowcount > 0
    
    def close(self):
        if self.conn:
            self.conn.close()
            self.conn = None
