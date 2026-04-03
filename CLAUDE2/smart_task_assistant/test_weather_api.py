#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
测试和风天气API
"""
import requests
import json

# API密钥
API_KEY = "62abea70a8e24a02bec7b26e39868fd8"
# 自定义Host
BASE_URL = "https://ma6yw23g2n.re.qweatherapi.com"

def test_city_lookup(city_name):
    """测试城市查询API"""
    print(f"\n{'='*60}")
    print(f"测试1: 城市查询 - {city_name}")
    print(f"{'='*60}")
    
    url = f"{BASE_URL}/v2/city/lookup"
    params = {
        'location': city_name,
        'key': API_KEY
    }
    
    try:
        response = requests.get(url, params=params, timeout=10)
        print(f"请求URL: {response.url}")
        print(f"状态码: {response.status_code}")
        
        if response.status_code == 200:
            data = response.json()
            print(f"响应数据:\n{json.dumps(data, ensure_ascii=False, indent=2)}")
            
            # 检查是否有城市数据
            if data.get('code') == '200' and data.get('location'):
                locations = data['location']
                print(f"\n✅ 成功找到 {len(locations)} 个城市:")
                for loc in locations[:3]:  # 只显示前3个
                    print(f"   - {loc['name']} ({loc.get('adm1', '')}) - ID: {loc['id']}")
                return locations[0]['id']
            else:
                print(f"\n❌ API返回错误: {data.get('code')} - {data.get('message')}")
                return None
        else:
            print(f"\n❌ HTTP错误: {response.status_code}")
            return None
    except Exception as e:
        print(f"\n❌ 请求异常: {e}")
        return None

def test_weather_now(city_id):
    """测试实时天气API"""
    print(f"\n{'='*60}")
    print(f"测试2: 实时天气 - 城市ID: {city_id}")
    print(f"{'='*60}")
    
    url = f"{BASE_URL}/v7/weather/now"
    params = {
        'location': city_id,
        'key': API_KEY
    }
    
    try:
        response = requests.get(url, params=params, timeout=10)
        print(f"请求URL: {response.url}")
        print(f"状态码: {response.status_code}")
        
        if response.status_code == 200:
            data = response.json()
            print(f"响应数据:\n{json.dumps(data, ensure_ascii=False, indent=2)}")
            
            # 检查是否有天气数据
            if data.get('code') == '200' and data.get('now'):
                now = data['now']
                print(f"\n✅ 天气数据获取成功:")
                print(f"   城市: {data.get('basic', {}).get('location', '')}")
                print(f"   温度: {now.get('temp')}°C")
                print(f"   天气: {now.get('text')}")
                print(f"   风向: {now.get('windDir')}")
                print(f"   风力: {now.get('windScale')}级")
                print(f"   湿度: {now.get('humidity')}%")
                print(f"   体感温度: {now.get('feelsLike')}°C")
                return {
                    'cityName': data.get('basic', {}).get('location', ''),
                    'temperature': int(now.get('temp', 0)),
                    'temperatureText': f"{now.get('temp', '0')}°C",
                    'description': now.get('text', ''),
                    'windDirection': now.get('windDir', ''),
                    'windSpeed': now.get('windScale', ''),
                    'humidity': now.get('humidity', ''),
                    'feelsLike': now.get('feelsLike', '')
                }
            else:
                print(f"\n❌ API返回错误: {data.get('code')} - {data.get('message')}")
                return None
        else:
            print(f"\n❌ HTTP错误: {response.status_code}")
            return None
    except Exception as e:
        print(f"\n❌ 请求异常: {e}")
        return None

def main():
    print("\n" + "="*60)
    print("和风天气API测试工具")
    print("="*60)
    
    # 测试多个城市
    test_cities = ['北京', '上海', '广州', '深圳', '杭州']
    
    for city in test_cities:
        print(f"\n\n{'#'*60}")
        print(f"测试城市: {city}")
        print(f"{'#'*60}")
        
        # 步骤1: 查询城市ID
        city_id = test_city_lookup(city)
        
        if city_id:
            # 步骤2: 获取天气
            weather = test_weather_now(city_id)
            
            if weather:
                print(f"\n{'='*60}")
                print(f"✅ {city} 测试成功!")
                print(f"   温度: {weather['temperatureText']}")
                print(f"   天气: {weather['description']}")
                print(f"{'='*60}")
            else:
                print(f"\n{'='*60}")
                print(f"❌ {city} 天气获取失败")
                print(f"{'='*60}")
        else:
            print(f"\n{'='*60}")
            print(f"❌ {city} 城市查询失败")
            print(f"{'='*60}")
    
    print(f"\n\n{'='*60}")
    print("测试完成!")
    print(f"{'='*60}\n")

if __name__ == "__main__":
    main()