"""
智能任务建议模块 - AI分析和建议
"""

import json
from datetime import datetime, timedelta
from typing import List, Dict, Any, Optional
from core.database import DatabaseManager


class SmartSuggestionService:
    def __init__(self, db: DatabaseManager, recognition_service=None):
        self.db = db
        self.recognition = recognition_service
    
    def get_smart_suggestions(self) -> List[Dict[str, Any]]:
        suggestions = []
        
        suggestions.extend(self._analyze_overdue_patterns())
        suggestions.extend(self._analyze_priority_balance())
        suggestions.extend(self._analyze_completion_patterns())
        suggestions.extend(self._suggest_best_times())
        
        ai_suggestions = self._get_ai_suggestions()
        if ai_suggestions:
            suggestions = ai_suggestions + suggestions
        
        return suggestions
    
    def _get_ai_suggestions(self) -> List[Dict[str, Any]]:
        if not self.recognition or not self.recognition.ai_service:
            return []
        
        try:
            all_tasks = self.db.get_all_tasks()
            if not all_tasks:
                return []
            
            overdue_tasks = self.db.get_overdue_tasks()
            stats = self.db.get_efficiency_stats()
            trend = self.db.get_completion_trend(7)
            
            pending_tasks = [t for t in all_tasks if t.get('status') == 'pending']
            
            task_summary = []
            for task in pending_tasks[:30]:
                task_summary.append({
                    'id': task.get('id'),
                    'title': task.get('title', ''),
                    'content': task.get('content', '')[:100] if task.get('content') else '',
                    'priority': task.get('priority', ''),
                    'deadline': task.get('deadline', '')
                })
            
            prompt = f"""请分析以下任务数据，提供智能建议和优先执行任务推荐。

待处理任务列表（前30个）：
{json.dumps(task_summary, ensure_ascii=False, indent=2)}

统计数据：
- 总任务数：{stats.get('total', 0)}
- 完成率：{stats.get('completion_rate', 0)}%
- 平均完成天数：{stats.get('avg_completion_days', 0)}
- 逾期率：{stats.get('overdue_rate', 0)}%
- 逾期任务数：{len(overdue_tasks)}
- 优先级分布：{stats.get('priority_distribution', {})}

近7天趋势：
{json.dumps(trend, ensure_ascii=False, indent=2)}

请从以下维度分析并提供具体建议：
1. 任务内容分析：分析各任务的内容和关联性，识别关键任务
2. 优先执行任务推荐：根据任务内容、截止时间、优先级，推荐3-5个应该优先执行的任务，并说明理由
3. 逾期模式分析：分析逾期原因，提供改进建议
4. 优先级平衡分析：评估优先级设置是否合理
5. 完成模式分析：分析任务完成效率，提供提升建议

请以JSON格式返回，格式如下：
{{
    "priority_tasks": [
        {{
            "task_id": 任务ID,
            "title": "任务标题",
            "reason": "推荐理由",
            "suggested_order": 推荐执行顺序(1-5)
        }}
    ],
    "suggestions": [
        {{
            "type": "urgent/warning/info/success/tip",
            "title": "建议标题",
            "content": "详细内容",
            "action": "行动按钮文字（可选）",
            "priority": "high/medium/low"
        }}
    ]
}}

只返回JSON，不要有其他内容。"""
            
            result = self._call_ai(prompt)
            
            if isinstance(result, dict):
                suggestions = result.get('suggestions', [])
                priority_tasks = result.get('priority_tasks', [])
                if priority_tasks:
                    suggestions.insert(0, {
                        'type': 'tip',
                        'title': '📋 优先执行任务推荐',
                        'content': 'AI根据任务内容和优先级分析，推荐以下任务优先执行',
                        'priority_tasks': priority_tasks,
                        'priority': 'high'
                    })
                return suggestions
            
            if isinstance(result, str):
                try:
                    start = result.find('{')
                    end = result.rfind('}') + 1
                    if start != -1 and end > start:
                        data = json.loads(result[start:end])
                        suggestions = data.get('suggestions', [])
                        priority_tasks = data.get('priority_tasks', [])
                        if priority_tasks:
                            suggestions.insert(0, {
                                'type': 'tip',
                                'title': '📋 优先执行任务推荐',
                                'content': 'AI根据任务内容和优先级分析，推荐以下任务优先执行',
                                'priority_tasks': priority_tasks,
                                'priority': 'high'
                            })
                        return suggestions
                except:
                    pass
            
        except Exception as e:
            print(f"AI分析失败: {e}")
        
        return []
    
    def _call_ai(self, prompt: str):
        ai_service = self.recognition.ai_service
        
        if ai_service.api_type == 'local_llm':
            return self._call_local_llm(ai_service, prompt)
        elif ai_service.api_type == 'remote_api':
            return self._call_remote_api(ai_service, prompt)
        
        return None
    
    def _call_local_llm(self, ai_service, prompt: str):
        try:
            import requests
            
            model = ai_service.model if ai_service.model else 'qwen2.5:7b'
            
            system_prompt = """你是一位专业的任务管理智能助手，拥有丰富的时间管理和项目规划经验。你的职责是帮助用户分析任务数据，提供专业的建议和优先执行任务推荐。

你的核心能力：
1. 任务内容分析：深入理解任务内容，识别任务之间的关联性和依赖关系
2. 优先级判断：综合考虑截止时间、任务重要性、紧急程度等因素，合理判断任务优先级
3. 风险预警：识别可能逾期或存在风险的任务，提前预警
4. 效率优化：分析任务完成模式，提供效率提升建议
5. 行动建议：给出具体、可执行的下一步行动建议

输出要求：
- 必须严格返回JSON格式，不要包含任何其他文字说明
- 建议内容要具体、可操作，避免泛泛而谈
- 优先任务推荐要给出明确的理由
- 语言简洁专业，突出重点"""

            response = requests.post(
                f'{ai_service.api_base}/v1/chat/completions',
                headers={'Content-Type': 'application/json'},
                json={
                    'model': model,
                    'messages': [
                        {'role': 'system', 'content': system_prompt},
                        {'role': 'user', 'content': prompt}
                    ],
                    'temperature': 0.7
                },
                timeout=60
            )
            
            if response.status_code == 200:
                result = response.json()
                return result['choices'][0]['message']['content']
            else:
                print(f"Local LLM调用失败: {response.status_code}")
        except Exception as e:
            print(f"Local LLM调用失败: {e}")
        
        return None
    
    def _call_remote_api(self, ai_service, prompt: str):
        try:
            import requests
            
            model = ai_service.model if ai_service.model else 'gpt-3.5-turbo'
            
            system_prompt = """你是一位专业的任务管理智能助手，拥有丰富的时间管理和项目规划经验。你的职责是帮助用户分析任务数据，提供专业的建议和优先执行任务推荐。

你的核心能力：
1. 任务内容分析：深入理解任务内容，识别任务之间的关联性和依赖关系
2. 优先级判断：综合考虑截止时间、任务重要性、紧急程度等因素，合理判断任务优先级
3. 风险预警：识别可能逾期或存在风险的任务，提前预警
4. 效率优化：分析任务完成模式，提供效率提升建议
5. 行动建议：给出具体、可执行的下一步行动建议

输出要求：
- 必须严格返回JSON格式，不要包含任何其他文字说明
- 建议内容要具体、可操作，避免泛泛而谈
- 优先任务推荐要给出明确的理由
- 语言简洁专业，突出重点"""

            response = requests.post(
                f'{ai_service.api_base}/chat/completions',
                headers={
                    'Authorization': f'Bearer {ai_service.api_key}',
                    'Content-Type': 'application/json'
                },
                json={
                    'model': model,
                    'messages': [
                        {'role': 'system', 'content': system_prompt},
                        {'role': 'user', 'content': prompt}
                    ],
                    'temperature': 0.7
                },
                timeout=60
            )
            
            if response.status_code == 200:
                result = response.json()
                return result['choices'][0]['message']['content']
            else:
                print(f"Remote API调用失败: {response.status_code}")
        except Exception as e:
            print(f"Remote API调用失败: {e}")
        
        return None
    
    def _analyze_overdue_patterns(self) -> List[Dict[str, Any]]:
        suggestions = []
        
        overdue_tasks = self.db.get_overdue_tasks()
        if len(overdue_tasks) > 3:
            suggestions.append({
                'type': 'warning',
                'title': '逾期任务过多',
                'content': f'您有 {len(overdue_tasks)} 个任务已逾期，建议优先处理或重新安排截止时间。',
                'action': '查看逾期任务',
                'priority': 'high'
            })
        
        high_priority_overdue = [t for t in overdue_tasks if t.get('priority') == 'high']
        if high_priority_overdue:
            suggestions.append({
                'type': 'urgent',
                'title': '高优先级任务逾期',
                'content': f'有 {len(high_priority_overdue)} 个高优先级任务已逾期，请立即处理！',
                'action': '立即处理',
                'priority': 'high'
            })
        
        return suggestions
    
    def _analyze_priority_balance(self) -> List[Dict[str, Any]]:
        suggestions = []
        
        stats = self.db.get_efficiency_stats()
        priority_dist = stats.get('priority_distribution', {})
        
        total = sum(priority_dist.values())
        if total > 0:
            high_ratio = priority_dist.get('high', 0) / total
            if high_ratio > 0.5:
                suggestions.append({
                    'type': 'info',
                    'title': '优先级分布建议',
                    'content': '超过50%的任务被标记为高优先级，建议重新评估任务优先级，避免优先级膨胀。',
                    'action': '调整优先级',
                    'priority': 'medium'
                })
        
        return suggestions
    
    def _analyze_completion_patterns(self) -> List[Dict[str, Any]]:
        suggestions = []
        
        trend = self.db.get_completion_trend(7)
        
        completed_count = sum(d.get('completed', 0) for d in trend)
        created_count = sum(d.get('created', 0) for d in trend)
        
        if created_count > completed_count * 1.5:
            suggestions.append({
                'type': 'warning',
                'title': '任务积压预警',
                'content': f'近7天新建 {created_count} 个任务，仅完成 {completed_count} 个。建议适当减少新任务或提高完成效率。',
                'action': '查看统计',
                'priority': 'medium'
            })
        
        if completed_count > 0 and created_count == 0:
            suggestions.append({
                'type': 'success',
                'title': '效率提升',
                'content': f'近7天完成了 {completed_count} 个任务，继续保持！',
                'action': None,
                'priority': 'low'
            })
        
        return suggestions
    
    def _suggest_best_times(self) -> List[Dict[str, Any]]:
        suggestions = []
        
        now = datetime.now()
        hour = now.hour
        
        if 9 <= hour < 11:
            suggestions.append({
                'type': 'tip',
                'title': '黄金工作时间',
                'content': '上午9-11点是工作效率最高的时段，建议处理重要且紧急的任务。',
                'action': None,
                'priority': 'low'
            })
        elif 14 <= hour < 16:
            suggestions.append({
                'type': 'tip',
                'title': '下午工作时间',
                'content': '下午2-4点适合处理需要集中注意力的任务。',
                'action': None,
                'priority': 'low'
            })
        elif hour >= 17:
            suggestions.append({
                'type': 'tip',
                'title': '日终总结',
                'content': '建议花10分钟回顾今日完成的任务，规划明日工作。',
                'action': None,
                'priority': 'low'
            })
        
        return suggestions
    
    def decompose_task(self, task: Dict[str, Any]) -> List[Dict[str, Any]]:
        if not self.recognition:
            return self._simple_decompose(task)
        
        try:
            prompt = f"""请将以下任务分解为3-5个子任务，每个子任务应该是具体可执行的步骤。

任务标题：{task.get('title', '')}
任务内容：{task.get('content', '')}
验收标准：{task.get('acceptance_criteria', '')}

请以JSON格式返回子任务列表，格式如下：
[
    {{"title": "子任务标题", "content": "子任务内容", "priority": "high/medium/low"}}
]
"""
            result = self.recognition.recognize(prompt)
            if isinstance(result, list):
                return result
        except:
            pass
        
        return self._simple_decompose(task)
    
    def _simple_decompose(self, task: Dict[str, Any]) -> List[Dict[str, Any]]:
        title = task.get('title', '')
        
        subtasks = [
            {'title': f'准备：{title}', 'content': '收集相关资料和信息', 'priority': 'medium'},
            {'title': f'执行：{title}', 'content': '完成主要工作内容', 'priority': 'high'},
            {'title': f'检查：{title}', 'content': '验证完成质量', 'priority': 'medium'},
        ]
        
        return subtasks
    
    def suggest_priority(self, task: Dict[str, Any]) -> str:
        title = task.get('title', '').lower()
        content = task.get('content', '').lower()
        deadline = task.get('deadline', '')
        
        urgent_keywords = ['紧急', 'urgent', '立即', '马上', '尽快', '今天', '明天']
        important_keywords = ['重要', 'important', '关键', '核心', '必须']
        
        text = title + ' ' + content
        
        if any(kw in text for kw in urgent_keywords):
            return 'high'
        
        if any(kw in text for kw in important_keywords):
            return 'high'
        
        if deadline:
            try:
                if len(deadline) == 16:
                    deadline_dt = datetime.strptime(deadline, '%Y-%m-%d %H:%M')
                else:
                    deadline_dt = datetime.strptime(deadline, '%Y-%m-%d %H:%M:%S')
                
                days_until = (deadline_dt - datetime.now()).days
                
                if days_until <= 1:
                    return 'high'
                elif days_until <= 3:
                    return 'medium'
            except:
                pass
        
        return 'medium'
    
    def get_daily_plan(self) -> Dict[str, Any]:
        today_tasks = self.db.get_today_tasks()
        overdue_tasks = self.db.get_overdue_tasks()
        
        all_tasks = today_tasks + overdue_tasks
        
        high_priority = [t for t in all_tasks if t.get('priority') == 'high']
        medium_priority = [t for t in all_tasks if t.get('priority') == 'medium']
        low_priority = [t for t in all_tasks if t.get('priority') == 'low']
        
        plan = {
            'morning': high_priority[:3],
            'afternoon': medium_priority[:3],
            'evening': low_priority[:2],
            'total_tasks': len(all_tasks),
            'high_count': len(high_priority)
        }
        
        return plan
