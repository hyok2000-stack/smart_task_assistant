"""
数据库管理模块
"""

import sqlite3
import os
import uuid
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
                completed_at TEXT,
                sort_order INTEGER DEFAULT 0,
                is_recurring INTEGER DEFAULT 0,
                recurring_rule TEXT,
                parent_task_id TEXT,
                reminder_times TEXT
            )
        ''')
        
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS tags (
                tag_id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                color TEXT DEFAULT '#2196F3',
                created_at TEXT NOT NULL
            )
        ''')
        
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS task_tags (
                task_id TEXT,
                tag_id TEXT,
                PRIMARY KEY (task_id, tag_id)
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
            CREATE TABLE IF NOT EXISTS task_history (
                history_id TEXT PRIMARY KEY,
                task_id TEXT NOT NULL,
                action TEXT NOT NULL,
                old_value TEXT,
                new_value TEXT,
                created_at TEXT NOT NULL
            )
        ''')
        
        cursor.execute('''
            CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status)
        ''')
        
        cursor.execute('''
            CREATE INDEX IF NOT EXISTS idx_tasks_deadline ON tasks(deadline)
        ''')
        
        cursor.execute('''
            CREATE INDEX IF NOT EXISTS idx_tasks_sort_order ON tasks(sort_order)
        ''')
        
        cursor.execute('''
            CREATE INDEX IF NOT EXISTS idx_tasks_parent ON tasks(parent_task_id)
        ''')
        
        self._migrate_database(cursor)
        
        conn.commit()
    
    def _migrate_database(self, cursor):
        try:
            cursor.execute("SELECT sort_order FROM tasks LIMIT 1")
        except sqlite3.OperationalError:
            cursor.execute("ALTER TABLE tasks ADD COLUMN sort_order INTEGER DEFAULT 0")
        
        try:
            cursor.execute("SELECT is_recurring FROM tasks LIMIT 1")
        except sqlite3.OperationalError:
            cursor.execute("ALTER TABLE tasks ADD COLUMN is_recurring INTEGER DEFAULT 0")
        
        try:
            cursor.execute("SELECT recurring_rule FROM tasks LIMIT 1")
        except sqlite3.OperationalError:
            cursor.execute("ALTER TABLE tasks ADD COLUMN recurring_rule TEXT")
        
        try:
            cursor.execute("SELECT parent_task_id FROM tasks LIMIT 1")
        except sqlite3.OperationalError:
            cursor.execute("ALTER TABLE tasks ADD COLUMN parent_task_id TEXT")
        
        try:
            cursor.execute("SELECT reminder_times FROM tasks LIMIT 1")
        except sqlite3.OperationalError:
            cursor.execute("ALTER TABLE tasks ADD COLUMN reminder_times TEXT")
    
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
    
    def delete_tasks(self, task_ids: List[str]) -> int:
        conn = self.get_connection()
        cursor = conn.cursor()
        
        placeholders = ','.join(['?' for _ in task_ids])
        cursor.execute(f'DELETE FROM tasks WHERE task_id IN ({placeholders})', task_ids)
        conn.commit()
        
        return cursor.rowcount
    
    def update_tasks_status(self, task_ids: List[str], status: str) -> int:
        conn = self.get_connection()
        cursor = conn.cursor()
        
        now = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        placeholders = ','.join(['?' for _ in task_ids])
        
        if status == 'completed':
            cursor.execute(
                f'UPDATE tasks SET status = ?, updated_at = ?, completed_at = ? WHERE task_id IN ({placeholders})',
                [status, now, now] + task_ids
            )
        else:
            cursor.execute(
                f'UPDATE tasks SET status = ?, updated_at = ? WHERE task_id IN ({placeholders})',
                [status, now] + task_ids
            )
        
        conn.commit()
        return cursor.rowcount
    
    def update_tasks_priority(self, task_ids: List[str], priority: str) -> int:
        conn = self.get_connection()
        cursor = conn.cursor()
        
        now = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        placeholders = ','.join(['?' for _ in task_ids])
        
        cursor.execute(
            f'UPDATE tasks SET priority = ?, updated_at = ? WHERE task_id IN ({placeholders})',
            [priority, now] + task_ids
        )
        
        conn.commit()
        return cursor.rowcount
    
    def update_task_order(self, task_orders: Dict[str, int]) -> bool:
        conn = self.get_connection()
        cursor = conn.cursor()
        
        for task_id, order in task_orders.items():
            cursor.execute(
                'UPDATE tasks SET sort_order = ? WHERE task_id = ?',
                (order, task_id)
            )
        
        conn.commit()
        return True
    
    def get_sub_tasks(self, parent_task_id: str) -> List[Dict[str, Any]]:
        conn = self.get_connection()
        cursor = conn.cursor()
        
        cursor.execute(
            'SELECT * FROM tasks WHERE parent_task_id = ? ORDER BY sort_order, created_at',
            (parent_task_id,)
        )
        rows = cursor.fetchall()
        
        return [dict(row) for row in rows]
    
    def search_tasks(self, keyword: str) -> List[Dict[str, Any]]:
        conn = self.get_connection()
        cursor = conn.cursor()
        
        cursor.execute('''
            SELECT * FROM tasks 
            WHERE title LIKE ? OR content LIKE ? OR original_content LIKE ?
            ORDER BY created_at DESC
        ''', (f'%{keyword}%', f'%{keyword}%', f'%{keyword}%'))
        rows = cursor.fetchall()
        
        return [dict(row) for row in rows]
    
    def get_completion_trend(self, days: int = 7) -> List[Dict[str, Any]]:
        conn = self.get_connection()
        cursor = conn.cursor()
        
        trend = []
        for i in range(days - 1, -1, -1):
            date = (datetime.now() - timedelta(days=i)).strftime('%Y-%m-%d')
            
            cursor.execute('''
                SELECT COUNT(*) FROM tasks 
                WHERE date(completed_at) = ?
            ''', (date,))
            completed = cursor.fetchone()[0]
            
            cursor.execute('''
                SELECT COUNT(*) FROM tasks 
                WHERE date(created_at) = ?
            ''', (date,))
            created = cursor.fetchone()[0]
            
            trend.append({
                'date': date,
                'completed': completed,
                'created': created
            })
        
        return trend
    
    def get_efficiency_stats(self) -> Dict[str, Any]:
        conn = self.get_connection()
        cursor = conn.cursor()
        
        stats = {}
        
        cursor.execute("SELECT COUNT(*) FROM tasks WHERE status = 'completed'")
        total_completed = cursor.fetchone()[0]
        
        cursor.execute('''
            SELECT AVG(julianday(completed_at) - julianday(created_at)) 
            FROM tasks WHERE status = 'completed' AND completed_at IS NOT NULL
        ''')
        avg_days = cursor.fetchone()[0] or 0
        stats['avg_completion_days'] = round(avg_days, 1)
        
        cursor.execute("SELECT COUNT(*) FROM tasks")
        total = cursor.fetchone()[0]
        stats['completion_rate'] = round(total_completed / total * 100, 1) if total > 0 else 0
        
        cursor.execute('''
            SELECT COUNT(*) FROM tasks 
            WHERE status NOT IN ('completed', 'cancelled')
            AND (
                (LENGTH(deadline) = 16 AND deadline || ':00' < ?) OR
                (LENGTH(deadline) > 16 AND deadline < ?)
            )
        ''', (datetime.now().strftime('%Y-%m-%d %H:%M:%S'),) * 2)
        overdue = cursor.fetchone()[0]
        stats['overdue_rate'] = round(overdue / total * 100, 1) if total > 0 else 0
        
        cursor.execute('''
            SELECT priority, COUNT(*) as cnt FROM tasks 
            GROUP BY priority ORDER BY cnt DESC
        ''')
        stats['priority_distribution'] = {row[0]: row[1] for row in cursor.fetchall()}
        
        return stats
    
    def insert_tag(self, tag: Dict[str, Any]) -> str:
        conn = self.get_connection()
        cursor = conn.cursor()
        
        cursor.execute('''
            INSERT INTO tags (tag_id, name, color, created_at)
            VALUES (?, ?, ?, ?)
        ''', (tag['tag_id'], tag['name'], tag.get('color', '#2196F3'), tag['created_at']))
        
        conn.commit()
        return tag['tag_id']
    
    def get_all_tags(self) -> List[Dict[str, Any]]:
        conn = self.get_connection()
        cursor = conn.cursor()
        
        cursor.execute('SELECT * FROM tags ORDER BY name ASC')
        rows = cursor.fetchall()
        
        return [dict(row) for row in rows]
    
    def update_tag(self, tag_id: str, updates: Dict[str, Any]) -> bool:
        conn = self.get_connection()
        cursor = conn.cursor()
        
        set_clause = ', '.join([f'{k} = ?' for k in updates.keys()])
        values = list(updates.values()) + [tag_id]
        
        cursor.execute(f'UPDATE tags SET {set_clause} WHERE tag_id = ?', values)
        conn.commit()
        
        return cursor.rowcount > 0
    
    def delete_tag(self, tag_id: str) -> bool:
        conn = self.get_connection()
        cursor = conn.cursor()
        
        cursor.execute('DELETE FROM task_tags WHERE tag_id = ?', (tag_id,))
        cursor.execute('DELETE FROM tags WHERE tag_id = ?', (tag_id,))
        conn.commit()
        
        return cursor.rowcount > 0
    
    def add_task_tag(self, task_id: str, tag_id: str) -> bool:
        conn = self.get_connection()
        cursor = conn.cursor()
        
        try:
            cursor.execute(
                'INSERT INTO task_tags (task_id, tag_id) VALUES (?, ?)',
                (task_id, tag_id)
            )
            conn.commit()
            return True
        except:
            return False
    
    def remove_task_tag(self, task_id: str, tag_id: str) -> bool:
        conn = self.get_connection()
        cursor = conn.cursor()
        
        cursor.execute(
            'DELETE FROM task_tags WHERE task_id = ? AND tag_id = ?',
            (task_id, tag_id)
        )
        conn.commit()
        
        return cursor.rowcount > 0
    
    def get_task_tags(self, task_id: str) -> List[Dict[str, Any]]:
        conn = self.get_connection()
        cursor = conn.cursor()
        
        cursor.execute('''
            SELECT t.* FROM tags t
            JOIN task_tags tt ON t.tag_id = tt.tag_id
            WHERE tt.task_id = ?
        ''', (task_id,))
        rows = cursor.fetchall()
        
        return [dict(row) for row in rows]
    
    def get_tasks_by_tag(self, tag_id: str) -> List[Dict[str, Any]]:
        conn = self.get_connection()
        cursor = conn.cursor()
        
        cursor.execute('''
            SELECT t.* FROM tasks t
            JOIN task_tags tt ON t.task_id = tt.task_id
            WHERE tt.tag_id = ?
            ORDER BY t.created_at DESC
        ''', (tag_id,))
        rows = cursor.fetchall()
        
        return [dict(row) for row in rows]
    
    def add_history(self, task_id: str, action: str, old_value: str = None, new_value: str = None):
        conn = self.get_connection()
        cursor = conn.cursor()
        
        history_id = f"H{uuid.uuid4().hex[:8].upper()}" if 'uuid' in dir() else f"H{hash(task_id + action + str(datetime.now()))}"
        
        cursor.execute('''
            INSERT INTO task_history (history_id, task_id, action, old_value, new_value, created_at)
            VALUES (?, ?, ?, ?, ?, ?)
        ''', (history_id, task_id, action, old_value, new_value, datetime.now().strftime('%Y-%m-%d %H:%M:%S')))
        
        conn.commit()
    
    def get_task_history(self, task_id: str) -> List[Dict[str, Any]]:
        conn = self.get_connection()
        cursor = conn.cursor()
        
        cursor.execute(
            'SELECT * FROM task_history WHERE task_id = ? ORDER BY created_at DESC',
            (task_id,)
        )
        rows = cursor.fetchall()
        
        return [dict(row) for row in rows]
    
    def export_tasks(self, task_ids: List[str] = None) -> List[Dict[str, Any]]:
        conn = self.get_connection()
        cursor = conn.cursor()
        
        if task_ids:
            placeholders = ','.join(['?' for _ in task_ids])
            cursor.execute(f'SELECT * FROM tasks WHERE task_id IN ({placeholders})', task_ids)
        else:
            cursor.execute('SELECT * FROM tasks ORDER BY created_at DESC')
        
        rows = cursor.fetchall()
        return [dict(row) for row in rows]
    
    def backup_database(self, backup_path: str) -> bool:
        try:
            import shutil
            shutil.copy2(self.db_path, backup_path)
            return True
        except:
            return False
    
    def restore_database(self, backup_path: str) -> bool:
        try:
            import shutil
            if self.conn:
                self.conn.close()
                self.conn = None
            shutil.copy2(backup_path, self.db_path)
            return True
        except:
            return False
    
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
