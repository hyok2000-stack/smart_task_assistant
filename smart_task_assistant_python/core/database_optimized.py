"""
数据库管理模块 - 优化版本
添加分页、缓存、批量操作优化
"""

import sqlite3
import os
import uuid
from datetime import datetime, timedelta
from typing import List, Optional, Dict, Any, Tuple
from functools import lru_cache
import threading
import time


class DatabaseManagerOptimized:
    def __init__(self, db_path: str):
        self.db_path = db_path
        self._cache = {}
        self._cache_time = {}
        self._cache_ttl = 5
        self._lock = threading.Lock()
        
    def get_connection(self):
        conn = sqlite3.connect(self.db_path, timeout=30.0)
        conn.row_factory = sqlite3.Row
        conn.execute('PRAGMA journal_mode=WAL')
        conn.execute('PRAGMA busy_timeout=30000')
        conn.execute('PRAGMA cache_size=-64000')
        conn.execute('PRAGMA temp_store=MEMORY')
        conn.execute('PRAGMA synchronous=NORMAL')
        return conn
    
    def _invalidate_cache(self, key: str = None):
        with self._lock:
            if key:
                self._cache.pop(key, None)
                self._cache_time.pop(key, None)
            else:
                self._cache.clear()
                self._cache_time.clear()
    
    def _get_cached(self, key: str):
        with self._lock:
            if key in self._cache:
                if time.time() - self._cache_time.get(key, 0) < self._cache_ttl:
                    return self._cache[key]
                else:
                    self._cache.pop(key, None)
                    self._cache_time.pop(key, None)
        return None
    
    def _set_cache(self, key: str, value: Any):
        with self._lock:
            self._cache[key] = value
            self._cache_time[key] = time.time()
    
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
        
        indexes = [
            'CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status)',
            'CREATE INDEX IF NOT EXISTS idx_tasks_deadline ON tasks(deadline)',
            'CREATE INDEX IF NOT EXISTS idx_tasks_sort_order ON tasks(sort_order)',
            'CREATE INDEX IF NOT EXISTS idx_tasks_parent ON tasks(parent_task_id)',
            'CREATE INDEX IF NOT EXISTS idx_tasks_created_at ON tasks(created_at)',
            'CREATE INDEX IF NOT EXISTS idx_tasks_priority ON tasks(priority)',
            'CREATE INDEX IF NOT EXISTS idx_tasks_owner ON tasks(owner_name)',
            'CREATE INDEX IF NOT EXISTS idx_task_history_task ON task_history(task_id)',
        ]
        
        for index_sql in indexes:
            cursor.execute(index_sql)
        
        self._migrate_database(cursor)
        
        conn.commit()
    
    def _migrate_database(self, cursor):
        migrations = [
            ('sort_order', 'INTEGER DEFAULT 0'),
            ('is_recurring', 'INTEGER DEFAULT 0'),
            ('recurring_rule', 'TEXT'),
            ('parent_task_id', 'TEXT'),
            ('reminder_times', 'TEXT'),
        ]
        
        for column_name, column_type in migrations:
            try:
                cursor.execute(f"SELECT {column_name} FROM tasks LIMIT 1")
            except sqlite3.OperationalError:
                cursor.execute(f"ALTER TABLE tasks ADD COLUMN {column_name} {column_type}")
    
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
        conn.close()
        
        self._invalidate_cache()
        return task['task_id']
    
    def get_tasks_paginated(self, page: int = 1, page_size: int = 50, 
                           status: str = '', priority: str = '', 
                           owner: str = '', title: str = '') -> Tuple[List[Dict], int]:
        cache_key = f'paginated_{page}_{page_size}_{status}_{priority}_{owner}_{title}'
        cached = self._get_cached(cache_key)
        if cached:
            return cached
        
        conn = self.get_connection()
        cursor = conn.cursor()
        
        where_clauses = []
        params = []
        
        if status and status != 'all':
            if status == 'overdue':
                now_str = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
                where_clauses.append('''
                    (
                        (LENGTH(deadline) = 16 AND deadline || ':00' < ?) OR
                        (LENGTH(deadline) > 16 AND deadline < ?)
                    )
                    AND status NOT IN (?, ?)
                ''')
                params.extend([now_str, now_str, 'completed', 'cancelled'])
            else:
                where_clauses.append('status = ?')
                params.append(status)
        
        if priority:
            where_clauses.append('priority = ?')
            params.append(priority)
        
        if owner:
            where_clauses.append('owner_name LIKE ?')
            params.append(f'%{owner}%')
        
        if title:
            where_clauses.append('title LIKE ?')
            params.append(f'%{title}%')
        
        where_sql = ' AND '.join(where_clauses) if where_clauses else '1=1'
        
        count_sql = f'SELECT COUNT(*) FROM tasks WHERE {where_sql}'
        cursor.execute(count_sql, params)
        total_count = cursor.fetchone()[0]
        
        offset = (page - 1) * page_size
        data_sql = f'''
            SELECT * FROM tasks 
            WHERE {where_sql}
            ORDER BY created_at DESC
            LIMIT ? OFFSET ?
        '''
        params.extend([page_size, offset])
        
        cursor.execute(data_sql, params)
        rows = cursor.fetchall()
        conn.close()
        
        tasks = [dict(row) for row in rows]
        result = (tasks, total_count)
        
        self._set_cache(cache_key, result)
        return result
    
    def get_all_tasks(self) -> List[Dict[str, Any]]:
        cached = self._get_cached('all_tasks')
        if cached:
            return cached
        
        conn = self.get_connection()
        cursor = conn.cursor()
        
        cursor.execute('SELECT * FROM tasks ORDER BY created_at DESC')
        rows = cursor.fetchall()
        conn.close()
        
        tasks = [dict(row) for row in rows]
        self._set_cache('all_tasks', tasks)
        return tasks
    
    def get_task_by_id(self, task_id: str) -> Optional[Dict[str, Any]]:
        cache_key = f'task_{task_id}'
        cached = self._get_cached(cache_key)
        if cached:
            return cached
        
        conn = self.get_connection()
        cursor = conn.cursor()
        
        cursor.execute('SELECT * FROM tasks WHERE task_id = ?', (task_id,))
        row = cursor.fetchone()
        conn.close()
        
        task = dict(row) if row else None
        if task:
            self._set_cache(cache_key, task)
        return task
    
    def get_tasks_by_status(self, status: str) -> List[Dict[str, Any]]:
        cache_key = f'tasks_status_{status}'
        cached = self._get_cached(cache_key)
        if cached:
            return cached
        
        conn = self.get_connection()
        cursor = conn.cursor()
        
        cursor.execute(
            'SELECT * FROM tasks WHERE status = ? ORDER BY created_at DESC',
            (status,)
        )
        rows = cursor.fetchall()
        conn.close()
        
        tasks = [dict(row) for row in rows]
        self._set_cache(cache_key, tasks)
        return tasks
    
    def get_today_tasks(self) -> List[Dict[str, Any]]:
        cache_key = 'today_tasks'
        cached = self._get_cached(cache_key)
        if cached:
            return cached
        
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
        conn.close()
        
        tasks = [dict(row) for row in rows]
        self._set_cache(cache_key, tasks)
        return tasks
    
    def get_overdue_tasks(self) -> List[Dict[str, Any]]:
        cache_key = 'overdue_tasks'
        cached = self._get_cached(cache_key)
        if cached:
            return cached
        
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
        conn.close()
        
        tasks = [dict(row) for row in rows]
        self._set_cache(cache_key, tasks)
        return tasks
    
    def get_tasks_by_filters(self, priority: str = '', owner: str = '', 
                             time_filter: str = '', title: str = '', tag_id: str = '',
                             status_filter: str = '') -> List[Dict[str, Any]]:
        cache_key = f'filters_{priority}_{owner}_{time_filter}_{title}_{tag_id}_{status_filter}'
        cached = self._get_cached(cache_key)
        if cached:
            return cached
        
        conn = self.get_connection()
        cursor = conn.cursor()
        
        if tag_id:
            query = '''
                SELECT DISTINCT t.* FROM tasks t
                INNER JOIN task_tags tt ON t.task_id = tt.task_id
                WHERE 1=1
            '''
        else:
            query = 'SELECT * FROM tasks WHERE 1=1'
        params = []
        
        if status_filter:
            if status_filter == 'overdue':
                now_str = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
                if tag_id:
                    query += '''
                        AND (
                            (LENGTH(t.deadline) = 16 AND t.deadline || ':00' < ?) OR
                            (LENGTH(t.deadline) > 16 AND t.deadline < ?)
                        )
                        AND t.status NOT IN (?, ?)
                    '''
                else:
                    query += '''
                        AND (
                            (LENGTH(deadline) = 16 AND deadline || ':00' < ?) OR
                            (LENGTH(deadline) > 16 AND deadline < ?)
                        )
                        AND status NOT IN (?, ?)
                    '''
                params.extend([now_str, now_str, 'completed', 'cancelled'])
            elif status_filter == 'all':
                pass
            else:
                if tag_id:
                    query += ' AND t.status = ?'
                else:
                    query += ' AND status = ?'
                params.append(status_filter)
        
        if priority:
            query += ' AND t.priority = ?' if tag_id else ' AND priority = ?'
            params.append(priority)
        
        if owner:
            query += ' AND t.owner_name LIKE ?' if tag_id else ' AND owner_name LIKE ?'
            params.append(f'%{owner}%')
        
        if title:
            query += ' AND t.title LIKE ?' if tag_id else ' AND title LIKE ?'
            params.append(f'%{title}%')
        
        if tag_id:
            query += ' AND tt.tag_id = ?'
            params.append(tag_id)
        
        now = datetime.now()
        
        if time_filter == 'today':
            today = now.strftime('%Y-%m-%d')
            query += ' AND date(t.deadline) = ?' if tag_id else ' AND date(deadline) = ?'
            params.append(today)
        elif time_filter == 'tomorrow':
            tomorrow = (now + timedelta(days=1)).strftime('%Y-%m-%d')
            query += ' AND date(t.deadline) = ?' if tag_id else ' AND date(deadline) = ?'
            params.append(tomorrow)
        elif time_filter == 'this_week':
            start_of_week = now - timedelta(days=now.weekday())
            end_of_week = start_of_week + timedelta(days=6)
            query += ' AND date(t.deadline) BETWEEN ? AND ?' if tag_id else ' AND date(deadline) BETWEEN ? AND ?'
            params.extend([start_of_week.strftime('%Y-%m-%d'), end_of_week.strftime('%Y-%m-%d')])
        elif time_filter == 'this_month':
            start_of_month = now.replace(day=1)
            if now.month == 12:
                end_of_month = now.replace(year=now.year + 1, month=1, day=1) - timedelta(days=1)
            else:
                end_of_month = now.replace(month=now.month + 1, day=1) - timedelta(days=1)
            query += ' AND date(t.deadline) BETWEEN ? AND ?' if tag_id else ' AND date(deadline) BETWEEN ? AND ?'
            params.extend([start_of_month.strftime('%Y-%m-%d'), end_of_month.strftime('%Y-%m-%d')])
        elif time_filter == 'overdue':
            now_str = now.strftime('%Y-%m-%d %H:%M:%S')
            if tag_id:
                query += '''
                    AND (
                        (LENGTH(t.deadline) = 16 AND t.deadline || ':00' < ?) OR
                        (LENGTH(t.deadline) > 16 AND t.deadline < ?)
                    )
                '''
            else:
                query += '''
                    AND (
                        (LENGTH(deadline) = 16 AND deadline || ':00' < ?) OR
                        (LENGTH(deadline) > 16 AND deadline < ?)
                    )
                '''
            params.extend([now_str, now_str])
        
        query += ' ORDER BY t.created_at DESC' if tag_id else ' ORDER BY created_at DESC'
        
        cursor.execute(query, params)
        rows = cursor.fetchall()
        conn.close()
        
        tasks = [dict(row) for row in rows]
        self._set_cache(cache_key, tasks)
        return tasks
    
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
        conn.close()
        
        self._invalidate_cache()
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
        conn.close()
        
        self._invalidate_cache()
        return cursor.rowcount > 0
    
    def delete_tasks(self, task_ids: List[str]) -> int:
        conn = self.get_connection()
        cursor = conn.cursor()
        
        placeholders = ','.join(['?' for _ in task_ids])
        cursor.execute(f'DELETE FROM tasks WHERE task_id IN ({placeholders})', task_ids)
        conn.commit()
        conn.close()
        
        self._invalidate_cache()
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
        conn.close()
        
        self._invalidate_cache()
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
        conn.close()
        
        self._invalidate_cache()
        return cursor.rowcount
    
    def get_task_stats(self) -> Dict[str, int]:
        cache_key = 'task_stats'
        cached = self._get_cached(cache_key)
        if cached:
            return cached
        
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
        
        conn.close()
        
        self._set_cache(cache_key, stats)
        return stats
    
    def get_completion_trend(self, days: int = 7) -> List[Dict[str, Any]]:
        cache_key = f'completion_trend_{days}'
        cached = self._get_cached(cache_key)
        if cached:
            return cached
        
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
        
        conn.close()
        
        self._set_cache(cache_key, trend)
        return trend
    
    def get_efficiency_stats(self) -> Dict[str, Any]:
        cache_key = 'efficiency_stats'
        cached = self._get_cached(cache_key)
        if cached:
            return cached
        
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
        
        conn.close()
        
        self._set_cache(cache_key, stats)
        return stats
    
    def search_tasks(self, keyword: str, limit: int = 100) -> List[Dict[str, Any]]:
        cache_key = f'search_{keyword}_{limit}'
        cached = self._get_cached(cache_key)
        if cached:
            return cached
        
        conn = self.get_connection()
        cursor = conn.cursor()
        
        cursor.execute('''
            SELECT * FROM tasks 
            WHERE title LIKE ? OR content LIKE ? OR original_content LIKE ?
            ORDER BY created_at DESC
            LIMIT ?
        ''', (f'%{keyword}%', f'%{keyword}%', f'%{keyword}%', limit))
        rows = cursor.fetchall()
        conn.close()
        
        tasks = [dict(row) for row in rows]
        self._set_cache(cache_key, tasks)
        return tasks
    
    def close(self):
        self._invalidate_cache()
