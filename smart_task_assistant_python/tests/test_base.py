"""
单元测试配置和工具
"""

import unittest
import os
import sys
import tempfile
import shutil
from pathlib import Path

project_root = Path(__file__).parent.parent
sys.path.insert(0, str(project_root))


class BaseTestCase(unittest.TestCase):
    """基础测试类，提供通用的测试设置和清理"""
    
    @classmethod
    def setUpClass(cls):
        cls.test_dir = tempfile.mkdtemp()
        cls.db_path = os.path.join(cls.test_dir, 'test_tasks.db')
        cls.config_path = os.path.join(cls.test_dir, 'test_config.json')
    
    @classmethod
    def tearDownClass(cls):
        import time
        time.sleep(0.1)
        
        if os.path.exists(cls.test_dir):
            try:
                shutil.rmtree(cls.test_dir)
            except PermissionError:
                pass
    
    def setUp(self):
        self._setup_test_database()
        self._clear_database()
    
    def tearDown(self):
        self._cleanup_test_database()
    
    def _clear_database(self):
        conn = self.db.get_connection()
        cursor = conn.cursor()
        cursor.execute('DELETE FROM tasks')
        cursor.execute('DELETE FROM tags')
        cursor.execute('DELETE FROM task_tags')
        cursor.execute('DELETE FROM templates')
        cursor.execute('DELETE FROM task_history')
        conn.commit()
        conn.close()
    
    def _setup_test_database(self):
        from core.database import DatabaseManager
        self.db = DatabaseManager(self.db_path)
        self.db.init_database()
    
    def _cleanup_test_database(self):
        if hasattr(self, 'db'):
            try:
                self.db.close()
            except:
                pass
    
    def create_test_task(self, **kwargs):
        """创建测试任务"""
        from datetime import datetime
        import uuid
        
        defaults = {
            'task_id': f"T{uuid.uuid4().hex[:8].upper()}",
            'title': '测试任务',
            'content': '测试内容',
            'owner_name': '测试用户',
            'deadline': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
            'status': 'pending',
            'priority': 'medium',
            'created_at': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
            'updated_at': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
        }
        
        defaults.update(kwargs)
        return defaults


class DatabaseTestCase(BaseTestCase):
    """数据库测试基类"""
    
    def test_insert_task(self):
        """测试插入任务"""
        task = self.create_test_task()
        task_id = self.db.insert_task(task)
        
        self.assertIsNotNone(task_id)
        self.assertEqual(task_id, task['task_id'])
        
        retrieved = self.db.get_task_by_id(task_id)
        self.assertIsNotNone(retrieved)
        self.assertEqual(retrieved['title'], task['title'])
    
    def test_get_all_tasks(self):
        """测试获取所有任务"""
        for i in range(5):
            task = self.create_test_task(title=f'任务{i}')
            self.db.insert_task(task)
        
        tasks = self.db.get_all_tasks()
        self.assertEqual(len(tasks), 5)
    
    def test_update_task(self):
        """测试更新任务"""
        task = self.create_test_task()
        task_id = self.db.insert_task(task)
        
        updates = {
            'title': '更新后的标题',
            'status': 'in_progress'
        }
        
        result = self.db.update_task(task_id, updates)
        self.assertTrue(result)
        
        updated = self.db.get_task_by_id(task_id)
        self.assertEqual(updated['title'], '更新后的标题')
        self.assertEqual(updated['status'], 'in_progress')
    
    def test_delete_task(self):
        """测试删除任务"""
        task = self.create_test_task()
        task_id = self.db.insert_task(task)
        
        result = self.db.delete_task(task_id)
        self.assertTrue(result)
        
        deleted = self.db.get_task_by_id(task_id)
        self.assertIsNone(deleted)
    
    def test_get_tasks_by_status(self):
        """测试按状态获取任务"""
        for status in ['pending', 'in_progress', 'completed']:
            task = self.create_test_task(status=status)
            self.db.insert_task(task)
        
        pending_tasks = self.db.get_tasks_by_status('pending')
        self.assertEqual(len(pending_tasks), 1)
        self.assertEqual(pending_tasks[0]['status'], 'pending')
    
    def test_get_overdue_tasks(self):
        """测试获取逾期任务"""
        from datetime import datetime, timedelta
        
        overdue_task = self.create_test_task(
            deadline=(datetime.now() - timedelta(days=1)).strftime('%Y-%m-%d %H:%M:%S')
        )
        self.db.insert_task(overdue_task)
        
        future_task = self.create_test_task(
            deadline=(datetime.now() + timedelta(days=1)).strftime('%Y-%m-%d %H:%M:%S')
        )
        self.db.insert_task(future_task)
        
        overdue_tasks = self.db.get_overdue_tasks()
        self.assertEqual(len(overdue_tasks), 1)
    
    def test_search_tasks(self):
        """测试搜索任务"""
        task1 = self.create_test_task(title='Python开发任务')
        task2 = self.create_test_task(title='Java开发任务')
        task3 = self.create_test_task(title='测试任务')
        
        self.db.insert_task(task1)
        self.db.insert_task(task2)
        self.db.insert_task(task3)
        
        results = self.db.search_tasks('开发')
        self.assertEqual(len(results), 2)
        
        results = self.db.search_tasks('Python')
        self.assertEqual(len(results), 1)
    
    def test_get_task_stats(self):
        """测试获取任务统计"""
        for status in ['pending', 'pending', 'in_progress', 'completed']:
            task = self.create_test_task(status=status)
            self.db.insert_task(task)
        
        stats = self.db.get_task_stats()
        self.assertEqual(stats['total'], 4)
        self.assertEqual(stats['pending'], 2)
        self.assertEqual(stats['in_progress'], 1)
        self.assertEqual(stats['completed'], 1)


class AIServiceTestCase(BaseTestCase):
    """AI服务测试基类"""
    
    def test_local_recognition(self):
        """测试本地任务识别"""
        from core.ai_service import AIService
        
        ai_service = AIService(config={'ai_mode': 'local'})
        
        text = "明天下午3点前提交报告 @张三"
        result = ai_service.recognize_task(text)
        
        self.assertIsNotNone(result)
        self.assertIn('title', result)
        self.assertIn('deadline', result)
        self.assertIn('priority', result)
    
    def test_extract_title(self):
        """测试标题提取"""
        from core.ai_service import AIService
        
        ai_service = AIService(config={'ai_mode': 'local'})
        
        text = "明天下午3点前提交报告"
        title = ai_service._extract_title_local(text)
        
        self.assertIsNotNone(title)
        self.assertIn('提交报告', title)
    
    def test_extract_deadline(self):
        """测试截止时间提取"""
        from core.ai_service import AIService
        from datetime import datetime, timedelta
        
        ai_service = AIService(config={'ai_mode': 'local'})
        
        text = "明天下午3点前提交报告"
        deadline = ai_service._extract_deadline_local(text)
        
        self.assertIsNotNone(deadline)
        
        tomorrow = (datetime.now() + timedelta(days=1)).strftime('%Y-%m-%d')
        self.assertIn(tomorrow, deadline)
    
    def test_extract_priority(self):
        """测试优先级提取"""
        from core.ai_service import AIService
        
        ai_service = AIService(config={'ai_mode': 'local'})
        
        high_priority_text = "紧急处理这个任务"
        priority = ai_service._extract_priority_local(high_priority_text)
        self.assertEqual(priority, 'high')
        
        low_priority_text = "有空时处理这个任务"
        priority = ai_service._extract_priority_local(low_priority_text)
        self.assertEqual(priority, 'low')


def run_tests():
    """运行所有测试"""
    loader = unittest.TestLoader()
    suite = unittest.TestSuite()
    
    suite.addTests(loader.loadTestsFromTestCase(DatabaseTestCase))
    suite.addTests(loader.loadTestsFromTestCase(AIServiceTestCase))
    
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    
    return result.wasSuccessful()


if __name__ == '__main__':
    success = run_tests()
    sys.exit(0 if success else 1)
