"""
性能测试模块
"""

import unittest
import time
from datetime import datetime, timedelta
from tests.test_base import BaseTestCase


class PerformanceTestCase(BaseTestCase):
    """性能测试基类"""
    
    def setUp(self):
        super().setUp()
        self.performance_results = []
    
    def _measure_time(self, func, *args, **kwargs):
        """测量函数执行时间"""
        start_time = time.time()
        result = func(*args, **kwargs)
        end_time = time.time()
        
        duration = end_time - start_time
        self.performance_results.append({
            'function': func.__name__,
            'duration': duration,
            'timestamp': datetime.now().isoformat()
        })
        
        return result, duration
    
    def test_insert_performance(self):
        """测试插入性能"""
        task_count = 100
        
        _, duration = self._measure_time(self._insert_tasks, task_count)
        
        avg_time = duration / task_count
        self.assertLess(avg_time, 0.01, f"Average insert time {avg_time}s is too slow")
        
        print(f"\n插入 {task_count} 个任务耗时: {duration:.2f}s")
        print(f"平均每个任务: {avg_time*1000:.2f}ms")
    
    def _insert_tasks(self, count):
        """批量插入任务"""
        for i in range(count):
            task = self.create_test_task(title=f'性能测试任务{i}')
            self.db.insert_task(task)
    
    def test_query_performance(self):
        """测试查询性能"""
        for i in range(100):
            task = self.create_test_task(
                title=f'查询测试任务{i}',
                priority=['high', 'medium', 'low'][i % 3],
                status=['pending', 'in_progress', 'completed'][i % 3]
            )
            self.db.insert_task(task)
        
        _, duration = self._measure_time(self.db.get_all_tasks)
        self.assertLess(duration, 0.1, f"Query time {duration}s is too slow")
        print(f"\n查询所有任务耗时: {duration*1000:.2f}ms")
        
        _, duration = self._measure_time(
            self.db.get_tasks_by_filters,
            priority='high',
            status_filter='pending'
        )
        self.assertLess(duration, 0.05, f"Filter query time {duration}s is too slow")
        print(f"过滤查询耗时: {duration*1000:.2f}ms")
    
    def test_update_performance(self):
        """测试更新性能"""
        task_ids = []
        for i in range(50):
            task = self.create_test_task(title=f'更新测试任务{i}')
            task_id = self.db.insert_task(task)
            task_ids.append(task_id)
        
        _, duration = self._measure_time(
            self.db.update_tasks_status,
            task_ids,
            'completed'
        )
        
        avg_time = duration / len(task_ids)
        self.assertLess(avg_time, 0.005, f"Average update time {avg_time}s is too slow")
        print(f"\n批量更新 {len(task_ids)} 个任务耗时: {duration*1000:.2f}ms")
    
    def test_search_performance(self):
        """测试搜索性能"""
        for i in range(100):
            task = self.create_test_task(
                title=f'搜索测试任务{i} Python开发',
                content=f'任务内容{i} Java开发'
            )
            self.db.insert_task(task)
        
        _, duration = self._measure_time(self.db.search_tasks, 'Python')
        self.assertLess(duration, 0.05, f"Search time {duration}s is too slow")
        print(f"\n搜索耗时: {duration*1000:.2f}ms")
    
    def test_stats_performance(self):
        """测试统计性能"""
        for i in range(50):
            task = self.create_test_task(
                status=['pending', 'in_progress', 'completed'][i % 3]
            )
            self.db.insert_task(task)
        
        _, duration = self._measure_time(self.db.get_task_stats)
        self.assertLess(duration, 0.05, f"Stats time {duration}s is too slow")
        print(f"\n统计耗时: {duration*1000:.2f}ms")
    
    def test_concurrent_access(self):
        """测试并发访问"""
        import threading
        
        def insert_tasks(thread_id):
            for i in range(10):
                task = self.create_test_task(title=f'并发任务_{thread_id}_{i}')
                self.db.insert_task(task)
        
        threads = []
        for i in range(5):
            thread = threading.Thread(target=insert_tasks, args=(i,))
            threads.append(thread)
        
        start_time = time.time()
        
        for thread in threads:
            thread.start()
        
        for thread in threads:
            thread.join()
        
        duration = time.time() - start_time
        
        tasks = self.db.get_all_tasks()
        self.assertEqual(len(tasks), 50)
        
        print(f"\n并发插入 50 个任务耗时: {duration:.2f}s")


class DatabaseOptimizedPerformanceTest(BaseTestCase):
    """优化数据库性能测试"""
    
    def test_pagination_performance(self):
        """测试分页性能"""
        from core.database_optimized import DatabaseManagerOptimized
        
        db_optimized = DatabaseManagerOptimized(self.db_path)
        db_optimized.init_database()
        
        for i in range(200):
            task = self.create_test_task(title=f'分页测试任务{i}')
            db_optimized.insert_task(task)
        
        start_time = time.time()
        tasks, total = db_optimized.get_tasks_paginated(page=1, page_size=50)
        duration = time.time() - start_time
        
        self.assertEqual(len(tasks), 50)
        self.assertEqual(total, 200)
        self.assertLess(duration, 0.05, f"Pagination time {duration}s is too slow")
        
        print(f"\n分页查询耗时: {duration*1000:.2f}ms")
        
        db_optimized.close()
    
    def test_cache_performance(self):
        """测试缓存性能"""
        from core.database_optimized import DatabaseManagerOptimized
        
        db_optimized = DatabaseManagerOptimized(self.db_path)
        db_optimized.init_database()
        
        for i in range(100):
            task = self.create_test_task(title=f'缓存测试任务{i}')
            db_optimized.insert_task(task)
        
        start_time = time.time()
        tasks1 = db_optimized.get_all_tasks()
        first_duration = time.time() - start_time
        
        start_time = time.time()
        tasks2 = db_optimized.get_all_tasks()
        cached_duration = time.time() - start_time
        
        self.assertEqual(len(tasks1), 100)
        self.assertEqual(len(tasks2), 100)
        self.assertLess(cached_duration, first_duration, "Cache should be faster")
        
        print(f"\n首次查询: {first_duration*1000:.2f}ms")
        print(f"缓存查询: {cached_duration*1000:.2f}ms")
        print(f"性能提升: {(1 - cached_duration/first_duration)*100:.1f}%")
        
        db_optimized.close()


class AIServicePerformanceTest(BaseTestCase):
    """AI服务性能测试"""
    
    def test_local_recognition_performance(self):
        """测试本地识别性能"""
        from core.ai_service import AIService
        
        ai_service = AIService(config={'ai_mode': 'local'})
        
        test_texts = [
            "明天下午3点前提交报告 @张三",
            "下周一开会讨论方案，紧急",
            "月底前完成项目文档",
            "每周五下午2点开例会",
            "有空时整理一下代码"
        ]
        
        start_time = time.time()
        
        for text in test_texts * 10:
            result = ai_service.recognize_task(text)
        
        duration = time.time() - start_time
        avg_time = duration / 50
        
        self.assertLess(avg_time, 0.01, f"Recognition time {avg_time}s is too slow")
        print(f"\n识别 50 个任务耗时: {duration:.2f}s")
        print(f"平均每个任务: {avg_time*1000:.2f}ms")


if __name__ == '__main__':
    unittest.main()
