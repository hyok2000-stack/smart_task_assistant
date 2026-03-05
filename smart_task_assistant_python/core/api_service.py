"""
API接口模块 - 提供REST API供外部系统调用
"""

import json
import uuid
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
from typing import Dict, Any, Optional, Callable
import threading


class TaskAPIHandler(BaseHTTPRequestHandler):
    db = None
    recognition = None
    
    def log_message(self, format, *args):
        pass
    
    def _send_response(self, status: int, data: Any):
        self.send_response(status)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()
        
        response = json.dumps(data, ensure_ascii=False)
        self.wfile.write(response.encode('utf-8'))
    
    def do_OPTIONS(self):
        self._send_response(200, {'status': 'ok'})
    
    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path
        query = parse_qs(parsed.query)
        
        try:
            if path == '/api/tasks':
                self._handle_get_tasks(query)
            elif path.startswith('/api/tasks/'):
                task_id = path.split('/')[-1]
                self._handle_get_task(task_id)
            elif path == '/api/stats':
                self._handle_get_stats()
            elif path == '/api/tags':
                self._handle_get_tags()
            elif path == '/api/health':
                self._send_response(200, {'status': 'healthy', 'timestamp': datetime.now().isoformat()})
            else:
                self._send_response(404, {'error': 'Not found'})
        except Exception as e:
            self._send_response(500, {'error': str(e)})
    
    def do_POST(self):
        parsed = urlparse(self.path)
        path = parsed.path
        
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length).decode('utf-8')
        
        try:
            data = json.loads(body) if body else {}
        except:
            self._send_response(400, {'error': 'Invalid JSON'})
            return
        
        try:
            if path == '/api/tasks':
                self._handle_create_task(data)
            elif path == '/api/tasks/batch-complete':
                self._handle_batch_complete(data)
            elif path == '/api/tasks/batch-delete':
                self._handle_batch_delete(data)
            elif path == '/api/tasks/search':
                self._handle_search_tasks(data)
            else:
                self._send_response(404, {'error': 'Not found'})
        except Exception as e:
            self._send_response(500, {'error': str(e)})
    
    def do_PUT(self):
        parsed = urlparse(self.path)
        path = parsed.path
        
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length).decode('utf-8')
        
        try:
            data = json.loads(body) if body else {}
        except:
            self._send_response(400, {'error': 'Invalid JSON'})
            return
        
        try:
            if path.startswith('/api/tasks/'):
                task_id = path.split('/')[-1]
                self._handle_update_task(task_id, data)
            else:
                self._send_response(404, {'error': 'Not found'})
        except Exception as e:
            self._send_response(500, {'error': str(e)})
    
    def do_DELETE(self):
        parsed = urlparse(self.path)
        path = parsed.path
        
        try:
            if path.startswith('/api/tasks/'):
                task_id = path.split('/')[-1]
                self._handle_delete_task(task_id)
            else:
                self._send_response(404, {'error': 'Not found'})
        except Exception as e:
            self._send_response(500, {'error': str(e)})
    
    def _handle_get_tasks(self, query: Dict):
        status = query.get('status', [None])[0]
        priority = query.get('priority', [None])[0]
        
        if status:
            tasks = self.db.get_tasks_by_status(status)
        elif priority:
            tasks = self.db.get_tasks_by_filters(priority=priority)
        else:
            tasks = self.db.get_all_tasks()
        
        for task in tasks:
            for key in task:
                if isinstance(task[key], bytes):
                    task[key] = task[key].decode('utf-8')
        
        self._send_response(200, {'tasks': tasks, 'count': len(tasks)})
    
    def _handle_get_task(self, task_id: str):
        task = self.db.get_task_by_id(task_id)
        if task:
            self._send_response(200, {'task': task})
        else:
            self._send_response(404, {'error': 'Task not found'})
    
    def _handle_get_stats(self):
        stats = self.db.get_task_stats()
        efficiency = self.db.get_efficiency_stats()
        self._send_response(200, {'stats': stats, 'efficiency': efficiency})
    
    def _handle_get_tags(self):
        tags = self.db.get_all_tags()
        self._send_response(200, {'tags': tags})
    
    def _handle_create_task(self, data: Dict):
        task_id = f"T{uuid.uuid4().hex[:8].upper()}"
        now = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        
        task = {
            'task_id': task_id,
            'title': data.get('title', '新任务'),
            'content': data.get('content', ''),
            'owner_name': data.get('owner_name', '我'),
            'deadline': data.get('deadline', now),
            'status': data.get('status', 'pending'),
            'priority': data.get('priority', 'medium'),
            'acceptance_criteria': data.get('acceptance_criteria', ''),
            'source_type': 'api',
            'original_content': data.get('original_content', ''),
            'tags': data.get('tags', ''),
            'created_at': now,
            'updated_at': now
        }
        
        self.db.insert_task(task)
        self._send_response(201, {'task': task, 'message': 'Task created'})
    
    def _handle_update_task(self, task_id: str, data: Dict):
        existing = self.db.get_task_by_id(task_id)
        if not existing:
            self._send_response(404, {'error': 'Task not found'})
            return
        
        self.db.update_task(task_id, data)
        updated = self.db.get_task_by_id(task_id)
        self._send_response(200, {'task': updated, 'message': 'Task updated'})
    
    def _handle_delete_task(self, task_id: str):
        existing = self.db.get_task_by_id(task_id)
        if not existing:
            self._send_response(404, {'error': 'Task not found'})
            return
        
        self.db.delete_task(task_id)
        self._send_response(200, {'message': 'Task deleted'})
    
    def _handle_batch_complete(self, data: Dict):
        task_ids = data.get('task_ids', [])
        if not task_ids:
            self._send_response(400, {'error': 'No task_ids provided'})
            return
        
        count = self.db.update_tasks_status(task_ids, 'completed')
        self._send_response(200, {'message': f'{count} tasks completed'})
    
    def _handle_batch_delete(self, data: Dict):
        task_ids = data.get('task_ids', [])
        if not task_ids:
            self._send_response(400, {'error': 'No task_ids provided'})
            return
        
        count = self.db.delete_tasks(task_ids)
        self._send_response(200, {'message': f'{count} tasks deleted'})
    
    def _handle_search_tasks(self, data: Dict):
        keyword = data.get('keyword', '')
        if not keyword:
            self._send_response(400, {'error': 'No keyword provided'})
            return
        
        tasks = self.db.search_tasks(keyword)
        self._send_response(200, {'tasks': tasks, 'count': len(tasks)})


class TaskAPIServer:
    def __init__(self, db, recognition=None, host: str = '127.0.0.1', port: int = 8080):
        self.db = db
        self.recognition = recognition
        self.host = host
        self.port = port
        self.server = None
        self.thread = None
    
    def start(self):
        TaskAPIHandler.db = self.db
        TaskAPIHandler.recognition = self.recognition
        
        self.server = HTTPServer((self.host, self.port), TaskAPIHandler)
        
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        
        return True
    
    def stop(self):
        if self.server:
            self.server.shutdown()
            self.server = None
    
    def get_url(self) -> str:
        return f"http://{self.host}:{self.port}"
    
    def get_endpoints(self) -> list:
        return [
            {'method': 'GET', 'path': '/api/tasks', 'description': '获取所有任务'},
            {'method': 'GET', 'path': '/api/tasks/{id}', 'description': '获取单个任务'},
            {'method': 'GET', 'path': '/api/stats', 'description': '获取统计数据'},
            {'method': 'GET', 'path': '/api/tags', 'description': '获取所有标签'},
            {'method': 'GET', 'path': '/api/health', 'description': '健康检查'},
            {'method': 'POST', 'path': '/api/tasks', 'description': '创建任务'},
            {'method': 'POST', 'path': '/api/tasks/batch-complete', 'description': '批量完成任务'},
            {'method': 'POST', 'path': '/api/tasks/batch-delete', 'description': '批量删除任务'},
            {'method': 'POST', 'path': '/api/tasks/search', 'description': '搜索任务'},
            {'method': 'PUT', 'path': '/api/tasks/{id}', 'description': '更新任务'},
            {'method': 'DELETE', 'path': '/api/tasks/{id}', 'description': '删除任务'},
        ]
