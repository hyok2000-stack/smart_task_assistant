"""
AI服务模块 - 支持多种AI接口
"""

import json
import re
from typing import Dict, Any, Optional
from datetime import datetime, timedelta

class AIService:
    def __init__(self, api_type: str = 'local', api_key: str = '', api_base: str = ''):
        self.api_type = api_type
        self.api_key = api_key
        self.api_base = api_base or self._get_default_base(api_type)
    
    def _get_default_base(self, api_type: str) -> str:
        bases = {
            'doubao': 'https://ark.cn-beijing.volces.com/api/v3',
            'kimi': 'https://api.moonshot.cn/v1',
            'openai': 'https://api.openai.com/v1',
        }
        return bases.get(api_type, '')
    
    def recognize_task(self, text: str) -> Dict[str, Any]:
        if self.api_type == 'doubao' and self.api_key:
            return self._recognize_with_doubao(text)
        elif self.api_type == 'kimi' and self.api_key:
            return self._recognize_with_kimi(text)
        elif self.api_type == 'openai' and self.api_key:
            return self._recognize_with_openai(text)
        elif self.api_type == 'qwen' and self.api_key:
            return self._recognize_with_qwen(text)
        elif self.api_type == 'zhipu' and self.api_key:
            return self._recognize_with_zhipu(text)
        else:
            return self._recognize_with_local(text)
    
    def _build_prompt(self, text: str) -> str:
        today = datetime.now()
        tomorrow = today + timedelta(days=1)
        return f"""你是一个专业的任务信息提取助手。请从以下文本中提取任务信息。

【输入文本】
{text}

【当前时间】
{today.strftime('%Y-%m-%d %H:%M')}，星期{['一','二','三','四','五','六','日'][today.weekday()]}

【提取要求】
1. 标题(title)：简洁概括任务内容，不超过20字，去除时间、人物等修饰词
2. 负责人(owner)：识别"@某人"、"由XX负责"、"交给XX"等，无人则返回null
3. 截止时间(deadline)：
   - 格式：YYYY-MM-DD HH:MM（年份必须是{today.year}年）
   - "今天"→{today.strftime('%Y-%m-%d')}
   - "明天"→{tomorrow.strftime('%Y-%m-%d')}
   - 时间限制：只能在工作时间09:00-18:00之间
   - 如果提到"凌晨"、"早上"、"上午"等，默认设为09:00
   - 如果提到"下午"、"晚上"等，默认设为18:00
   - 如果提到"中午"，默认设为12:00
   - 无明确时间则默认明天18:00
4. 优先级(priority)：
   - high：包含"紧急"、"着急"、"尽快"、"马上"、"重要"等词
   - low：包含"不急"、"有空"、"方便时"等词
   - medium：其他情况
5. 验收标准(acceptance)：根据任务内容生成可衡量的完成标准
6. 置信度(confidence)：0.0-1.0，表示提取结果的可靠程度

【返回格式】
仅返回JSON，不要包含其他内容：
{{"title":"任务标题","owner":"负责人或null","deadline":"YYYY-MM-DD HH:MM","priority":"high/medium/low","acceptance":"验收标准","confidence":0.9}}"""

    def _recognize_with_openai(self, text: str) -> Dict[str, Any]:
        try:
            import requests
            
            prompt = self._build_prompt(text)

            response = requests.post(
                f'{self.api_base}/chat/completions',
                headers={
                    'Authorization': f'Bearer {self.api_key}',
                    'Content-Type': 'application/json'
                },
                json={
                    'model': 'gpt-3.5-turbo',
                    'messages': [
                        {'role': 'system', 'content': '你是一个专业的任务信息提取助手，严格按照JSON格式返回结果。'},
                        {'role': 'user', 'content': prompt}
                    ],
                    'temperature': 0.1
                },
                timeout=30
            )
            
            if response.status_code == 200:
                result = response.json()
                content = result['choices'][0]['message']['content']
                return self._parse_ai_response(content, text)
            else:
                print(f'OpenAI API error: {response.status_code}')
                return self._recognize_with_local(text)
                
        except Exception as e:
            print(f'OpenAI API error: {e}')
            return self._recognize_with_local(text)
    
    def _recognize_with_qwen(self, text: str) -> Dict[str, Any]:
        try:
            import requests
            
            prompt = self._build_prompt(text)

            response = requests.post(
                'https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation',
                headers={
                    'Authorization': f'Bearer {self.api_key}',
                    'Content-Type': 'application/json'
                },
                json={
                    'model': 'qwen-turbo',
                    'input': {'messages': [
                        {'role': 'system', 'content': '你是一个专业的任务信息提取助手，严格按照JSON格式返回结果，不要包含任何其他文字。'},
                        {'role': 'user', 'content': prompt}
                    ]},
                    'parameters': {'temperature': 0.1, 'result_format': 'message'}
                },
                timeout=30
            )
            
            if response.status_code == 200:
                result = response.json()
                if 'output' in result and 'choices' in result['output']:
                    content = result['output']['choices'][0]['message']['content']
                    return self._parse_ai_response(content, text)
                else:
                    print(f'Qwen API unexpected response: {result}')
                    return self._recognize_with_local(text)
            else:
                print(f'Qwen API error: {response.status_code} - {response.text[:200]}')
                return self._recognize_with_local(text)
                
        except Exception as e:
            print(f'Qwen API error: {e}')
            return self._recognize_with_local(text)
    
    def _recognize_with_zhipu(self, text: str) -> Dict[str, Any]:
        try:
            import requests
            
            prompt = self._build_prompt(text)

            response = requests.post(
                'https://open.bigmodel.cn/api/paas/v4/chat/completions',
                headers={
                    'Authorization': f'Bearer {self.api_key}',
                    'Content-Type': 'application/json'
                },
                json={
                    'model': 'glm-4-flash',
                    'messages': [
                        {'role': 'system', 'content': '你是一个专业的任务信息提取助手，严格按照JSON格式返回结果。'},
                        {'role': 'user', 'content': prompt}
                    ],
                    'temperature': 0.1
                },
                timeout=30
            )
            
            if response.status_code == 200:
                result = response.json()
                content = result['choices'][0]['message']['content']
                return self._parse_ai_response(content, text)
            else:
                print(f'Zhipu API error: {response.status_code}')
                return self._recognize_with_local(text)
                
        except Exception as e:
            print(f'Zhipu API error: {e}')
            return self._recognize_with_local(text)
    
    def _recognize_with_doubao(self, text: str) -> Dict[str, Any]:
        try:
            import requests
            
            prompt = self._build_prompt(text)
            api_base = self.api_base or 'https://ark.cn-beijing.volces.com/api/v3'

            response = requests.post(
                f'{api_base}/chat/completions',
                headers={
                    'Authorization': f'Bearer {self.api_key}',
                    'Content-Type': 'application/json'
                },
                json={
                    'model': 'doubao-pro-32k-241215',
                    'messages': [
                        {'role': 'system', 'content': '你是一个专业的任务信息提取助手，严格按照JSON格式返回结果。'},
                        {'role': 'user', 'content': prompt}
                    ],
                    'temperature': 0.1
                },
                timeout=30
            )
            
            if response.status_code == 200:
                result = response.json()
                content = result['choices'][0]['message']['content']
                return self._parse_ai_response(content, text)
            else:
                print(f'Doubao API error: {response.status_code} - {response.text[:200]}')
                return self._recognize_with_local(text)
                
        except Exception as e:
            print(f'Doubao API error: {e}')
            return self._recognize_with_local(text)
    
    def _recognize_with_kimi(self, text: str) -> Dict[str, Any]:
        try:
            import requests
            
            prompt = self._build_prompt(text)
            api_base = self.api_base or 'https://api.moonshot.cn/v1'

            response = requests.post(
                f'{api_base}/chat/completions',
                headers={
                    'Authorization': f'Bearer {self.api_key}',
                    'Content-Type': 'application/json'
                },
                json={
                    'model': 'moonshot-v1-8k',
                    'messages': [
                        {'role': 'system', 'content': '你是一个专业的任务信息提取助手，严格按照JSON格式返回结果。'},
                        {'role': 'user', 'content': prompt}
                    ],
                    'temperature': 0.1
                },
                timeout=30
            )
            
            if response.status_code == 200:
                result = response.json()
                content = result['choices'][0]['message']['content']
                return self._parse_ai_response(content, text)
            else:
                print(f'Kimi API error: {response.status_code} - {response.text[:200]}')
                return self._recognize_with_local(text)
                
        except Exception as e:
            print(f'Kimi API error: {e}')
            return self._recognize_with_local(text)
    
    def _parse_ai_response(self, content: str, original_text: str) -> Dict[str, Any]:
        try:
            content = content.strip()
            
            if '```json' in content:
                content = content.split('```json')[1].split('```')[0]
            elif '```' in content:
                content = content.split('```')[1].split('```')[0]
            
            json_match = re.search(r'\{[^{}]*\}', content, re.DOTALL)
            if json_match:
                data = json.loads(json_match.group())
                
                deadline = data.get('deadline', '')
                current_year = datetime.now().year
                if deadline:
                    if re.match(r'\d{4}-\d{2}-\d{2} \d{2}:\d{2}$', deadline):
                        deadline = deadline + ':00'
                    year_match = re.match(r'(\d{4})-', deadline)
                    if year_match:
                        year = int(year_match.group(1))
                        if year < current_year or year > current_year + 1:
                            deadline = deadline.replace(str(year), str(current_year))
                    elif not re.match(r'\d{4}-\d{2}-\d{2}', deadline):
                        deadline = self._extract_deadline_local(original_text)
                
                return {
                    'title': data.get('title', '') or self._extract_title_local(original_text),
                    'owner_name': data.get('owner') if data.get('owner') and data.get('owner') != 'null' else None,
                    'deadline': deadline or self._extract_deadline_local(original_text),
                    'priority': data.get('priority', 'medium'),
                    'acceptance_criteria': data.get('acceptance', '') or self._generate_acceptance_local('', original_text),
                    'confidence': float(data.get('confidence', 0.8)),
                    'content': original_text
                }
        except Exception as e:
            print(f'Parse AI response error: {e}')
        
        return self._recognize_with_local(original_text)
    
    def _recognize_with_local(self, text: str) -> Dict[str, Any]:
        title = self._extract_title_local(text)
        owner = self._extract_owner_local(text)
        deadline = self._extract_deadline_local(text)
        priority = self._extract_priority_local(text)
        acceptance = self._generate_acceptance_local(title, text)
        confidence = self._calculate_confidence(title, deadline, owner)
        
        return {
            'title': title,
            'owner_name': owner,
            'deadline': deadline,
            'priority': priority,
            'acceptance_criteria': acceptance,
            'confidence': confidence,
            'content': text
        }
    
    def _extract_title_local(self, text: str) -> str:
        title = text.strip()
        
        patterns = [
            r'今天|今日|明天|明日|后天|大后天',
            r'下周[一二三四五六日天]',
            r'本周[一二三四五六日天]',
            r'\d+天后|\d+周后',
            r'\d{1,2}月\d{1,2}[日号]?',
            r'\d{1,2}[点时]\d{0,2}分?',
            r'下午|上午|晚上|中午|早上',
            r'月底|月初',
            r'@\S+',
            r'由\S+负责|\S+负责|交给\S+|发给\S+',
            r'紧急|着急|重要|尽快|马上',
        ]
        
        for pattern in patterns:
            title = re.sub(pattern, '', title)
        
        title = re.sub(r'[，。！？、；：]', ' ', title)
        title = re.sub(r'\s+', ' ', title).strip()
        
        return title[:50] if len(title) > 50 else title
    
    def _extract_owner_local(self, text: str) -> Optional[str]:
        patterns = [
            (r'@(\S+)', 1),
            (r'由(\S+)负责', 1),
            (r'(\S+)负责', 1),
            (r'交给(\S+)', 1),
            (r'发给(\S+)', 1),
            (r'通知(\S+)', 1),
        ]
        
        for pattern, group in patterns:
            match = re.search(pattern, text)
            if match:
                name = match.group(group)
                if name and len(name) <= 10 and not re.search(r'[是为在的有和与]', name):
                    return name
        
        return None
    
    def _extract_deadline_local(self, text: str) -> str:
        now = datetime.now()
        base_date = None
        hour = 18
        minute = 0
        
        if re.search(r'今天|今日', text):
            base_date = now
        elif re.search(r'明天|明日', text):
            base_date = now + timedelta(days=1)
        elif re.search(r'后天', text):
            base_date = now + timedelta(days=2)
        elif re.search(r'大后天', text):
            base_date = now + timedelta(days=3)
        
        weekday_match = re.search(r'下周([一二三四五六日天])', text)
        if weekday_match:
            weekday_map = {'一': 0, '二': 1, '三': 2, '四': 3, '五': 4, '六': 5, '日': 6, '天': 6}
            target = weekday_map.get(weekday_match.group(1), 0)
            days_ahead = (target - now.weekday() + 7) % 7
            if days_ahead == 0:
                days_ahead = 7
            base_date = now + timedelta(days=days_ahead)
        
        days_match = re.search(r'(\d+)天后', text)
        if days_match:
            days = int(days_match.group(1))
            base_date = now + timedelta(days=days)
        
        date_match = re.search(r'(\d{1,2})月(\d{1,2})[日号]?', text)
        if date_match:
            month = int(date_match.group(1))
            day = int(date_match.group(2))
            year = now.year
            if month < now.month or (month == now.month and day < now.day):
                year += 1
            base_date = datetime(year, month, day)
        
        time_match = re.search(r'(\d{1,2})[点时](\d{0,2})分?', text)
        if time_match:
            hour = int(time_match.group(1))
            minute = int(time_match.group(2)) if time_match.group(2) else 0
        
        if re.search(r'下午', text):
            if hour < 12:
                hour += 12
            if not time_match:
                hour = 14
        elif re.search(r'上午|早上|早晨', text):
            if not time_match:
                hour = 9
        elif re.search(r'晚上', text):
            if hour < 12:
                hour += 12
            if not time_match:
                hour = 20
        elif re.search(r'中午', text):
            if not time_match:
                hour = 12
        
        if base_date is None:
            base_date = now + timedelta(days=1)
            return base_date.replace(hour=18, minute=0, second=0).strftime('%Y-%m-%d %H:%M:%S')
        
        deadline_dt = base_date.replace(hour=hour, minute=minute, second=0)
        if deadline_dt.hour < 9:
            deadline_dt = deadline_dt.replace(hour=9)
        elif deadline_dt.hour > 18:
            deadline_dt = deadline_dt.replace(hour=18)
        
        return deadline_dt.strftime('%Y-%m-%d %H:%M:%S')
    
    def _extract_priority_local(self, text: str) -> str:
        if re.search(r'紧急|着急|急|马上|立刻|尽快|urgent', text, re.IGNORECASE):
            return 'high'
        if re.search(r'重要|关键|核心|important', text, re.IGNORECASE):
            return 'high'
        if re.search(r'不急|不着急|慢慢|有空时', text):
            return 'low'
        return 'medium'
    
    def _generate_acceptance_local(self, title: str, text: str) -> str:
        if '提交' in text or '发送' in text:
            return '已提交/发送'
        if '确认' in text or '审核' in text:
            return '已确认/审核通过'
        if '回复' in text:
            return '已回复'
        if title:
            return f'{title}已完成'
        return '任务已完成'
    
    def _calculate_confidence(self, title: str, deadline: str, owner: Optional[str]) -> float:
        confidence = 0.0
        if title:
            confidence += 0.4
        if deadline:
            confidence += 0.3
        if owner:
            confidence += 0.2
        if title and 5 < len(title) < 30:
            confidence += 0.1
        return min(confidence, 1.0)
