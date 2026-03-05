"""
核心模块单元测试
"""

import unittest
from datetime import datetime, timedelta
from tests.test_base import BaseTestCase


class TestDatabaseManager(BaseTestCase):
    """数据库管理器测试"""
    
    def test_batch_operations(self):
        """测试批量操作"""
        task_ids = []
        
        for i in range(10):
            task = self.create_test_task(title=f'批量任务{i}')
            task_id = self.db.insert_task(task)
            task_ids.append(task_id)
        
        count = self.db.update_tasks_status(task_ids, 'completed')
        self.assertEqual(count, 10)
        
        for task_id in task_ids:
            task = self.db.get_task_by_id(task_id)
            self.assertEqual(task['status'], 'completed')
    
    def test_filter_tasks(self):
        """测试任务过滤"""
        high_task = self.create_test_task(priority='high', title='高优先级任务')
        self.db.insert_task(high_task)
        
        medium_task = self.create_test_task(priority='medium', title='中优先级任务')
        self.db.insert_task(medium_task)
        
        low_task = self.create_test_task(priority='low', title='低优先级任务')
        self.db.insert_task(low_task)
        
        high_tasks = self.db.get_tasks_by_filters(priority='high')
        self.assertEqual(len(high_tasks), 1)
        
        title_tasks = self.db.get_tasks_by_filters(title='优先级')
        self.assertEqual(len(title_tasks), 3)
    
    def test_completion_trend(self):
        """测试完成趋势"""
        for i in range(7):
            task = self.create_test_task(
                status='completed',
                created_at=(datetime.now() - timedelta(days=i)).strftime('%Y-%m-%d %H:%M:%S')
            )
            self.db.insert_task(task)
        
        trend = self.db.get_completion_trend(7)
        self.assertEqual(len(trend), 7)
    
    def test_efficiency_stats(self):
        """测试效率统计"""
        for priority in ['high', 'medium', 'low']:
            task = self.create_test_task(priority=priority)
            self.db.insert_task(task)
        
        stats = self.db.get_efficiency_stats()
        
        self.assertIn('priority_distribution', stats)
        self.assertIn('completion_rate', stats)
        self.assertIn('avg_completion_days', stats)
    
    def test_tag_operations(self):
        """测试标签操作"""
        from core.database import DatabaseManager
        import uuid
        
        tag = {
            'tag_id': f"G{uuid.uuid4().hex[:8].upper()}",
            'name': '测试标签',
            'color': '#FF0000',
            'created_at': datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        }
        
        tag_id = self.db.insert_tag(tag)
        self.assertIsNotNone(tag_id)
        
        tags = self.db.get_all_tags()
        self.assertEqual(len(tags), 1)
        self.assertEqual(tags[0]['name'], '测试标签')
        
        task = self.create_test_task()
        task_id = self.db.insert_task(task)
        
        result = self.db.add_task_tag(task_id, tag_id)
        self.assertTrue(result)
        
        task_tags = self.db.get_task_tags(task_id)
        self.assertEqual(len(task_tags), 1)
        
        result = self.db.delete_tag(tag_id)
        self.assertTrue(result)


class TestAIService(BaseTestCase):
    """AI服务测试"""
    
    def test_recognize_with_local(self):
        """测试本地识别"""
        from core.ai_service import AIService
        
        ai_service = AIService(config={'ai_mode': 'local'})
        
        test_cases = [
            ("明天下午3点前提交报告", "提交报告"),
            ("下周一开会讨论方案", "开会讨论方案"),
            ("紧急处理这个bug", "处理这个bug"),
        ]
        
        for text, expected_keyword in test_cases:
            result = ai_service.recognize_task(text)
            self.assertIsNotNone(result)
            self.assertIn(expected_keyword, result['title'])
    
    def test_priority_detection(self):
        """测试优先级检测"""
        from core.ai_service import AIService
        
        ai_service = AIService(config={'ai_mode': 'local'})
        
        high_texts = [
            "紧急处理这个任务",
            "这个任务很重要",
            "马上完成",
            "尽快提交"
        ]
        
        for text in high_texts:
            priority = ai_service._extract_priority_local(text)
            self.assertEqual(priority, 'high', f"Failed for text: {text}")
        
        low_texts = [
            "有空时处理",
            "慢慢做"
        ]
        
        for text in low_texts:
            priority = ai_service._extract_priority_local(text)
            self.assertEqual(priority, 'low', f"Failed for text: {text}")
    
    def test_deadline_parsing(self):
        """测试截止时间解析"""
        from core.ai_service import AIService
        
        ai_service = AIService(config={'ai_mode': 'local'})
        
        now = datetime.now()
        
        text = "今天下午3点"
        deadline = ai_service._extract_deadline_local(text)
        self.assertIn(now.strftime('%Y-%m-%d'), deadline)
        
        text = "明天上午9点"
        deadline = ai_service._extract_deadline_local(text)
        tomorrow = (now + timedelta(days=1)).strftime('%Y-%m-%d')
        self.assertIn(tomorrow, deadline)
    
    def test_owner_extraction(self):
        """测试负责人提取"""
        from core.ai_service import AIService
        
        ai_service = AIService(config={'ai_mode': 'local'})
        
        test_cases = [
            ("@张三 完成这个任务", "张三"),
            ("由李四负责这个项目", "李四"),
        ]
        
        for text, expected_owner in test_cases:
            owner = ai_service._extract_owner_local(text)
            self.assertEqual(owner, expected_owner, f"Failed for text: {text}")
    
    def test_acceptance_generation(self):
        """测试验收标准生成"""
        from core.ai_service import AIService
        
        ai_service = AIService(config={'ai_mode': 'local'})
        
        text = "提交报告"
        acceptance = ai_service._generate_acceptance_local('提交报告', text)
        self.assertIn('提交', acceptance)


class TestClipboardService(BaseTestCase):
    """剪贴板服务测试"""
    
    def test_keyword_detection(self):
        """测试关键词检测"""
        from core.clipboard import ClipboardService
        
        service = ClipboardService()
        
        valid_texts = [
            "明天下午3点前提交报告",
            "下周一开会讨论",
            "@张三 完成这个任务",
        ]
        
        for text in valid_texts:
            result = service._is_valid_task_content(text)
            self.assertTrue(result, f"Should be valid: {text}")
        
        invalid_texts = [
            "https://example.com",
            "ab",
            ""
        ]
        
        for text in invalid_texts:
            result = service._is_valid_task_content(text)
            self.assertFalse(result, f"Should be invalid: {text}")


class TestReminderService(BaseTestCase):
    """提醒服务测试"""
    
    def test_reminder_calculation(self):
        """测试提醒时间计算"""
        from core.reminder_service import ReminderService
        from core.config import Config
        
        config = Config()
        config.settings['remind_minutes'] = 30
        
        service = ReminderService(self.db, config)
        
        upcoming = service.get_upcoming_reminders()
        self.assertIsInstance(upcoming, list)


class TestSmartSuggestion(BaseTestCase):
    """智能建议服务测试"""
    
    def test_suggestion_generation(self):
        """测试建议生成"""
        from core.smart_suggestion import SmartSuggestionService
        
        service = SmartSuggestionService(self.db)
        
        suggestions = service.get_smart_suggestions()
        self.assertIsInstance(suggestions, list)
    
    def test_priority_suggestion(self):
        """测试优先级建议"""
        from core.smart_suggestion import SmartSuggestionService
        
        service = SmartSuggestionService(self.db)
        
        urgent_task = self.create_test_task(
            title='紧急任务',
            deadline=datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        )
        
        priority = service.suggest_priority(urgent_task)
        self.assertEqual(priority, 'high')


if __name__ == '__main__':
    unittest.main()
