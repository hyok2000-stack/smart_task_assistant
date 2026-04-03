#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
测试和风天气官方API
"""
import requests
import json

# API密钥
API_KEY = "62abea70a8e24a02bec7b26e39868fd8"
# 官方Host
BASE_URL = "https://devapi.qweather.com/v7"

def test_weather_now_by_city(city_name):
    """通过城市名直接获取天气"""
    print(f"\n{'='*60}")
    print(f"测试: 实时天气 - {city_name}")
    print(f"{'='*60}")
    
    url = f"{BASE_URL}/weather/now"
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
                return True
            else:
                print(f"\n❌ API返回错误: {data.get('code')} - {data.get('message')}")
                return False
        else:
            print(f"\n❌ HTTP错误: {response.status_code}")
            return False
    except Exception as e:
        print(f"\n❌ 请求异常: {e}")
        return False

def main():
    print("\n" + "="*60)
    print("和风天气官方API测试工具")
    print("="*60)
    
    # 测试多个城市
    test_cities = ['101010100', '101020100', '101280101', '101280601']  # 北京、上海、广州、深圳的城市ID
    
    for city_id in test_cities:
        print(f"\n\n{'#'*60}")
        print(f"测试城市ID: {city_id}")
        print(f"{'#'*60}")
        
        success = test_weather_now_by_city(city_id)
        
        if success:
            print(f"\n{'='*60}")
            print(f"✅ 测试成功!")
            print(f"{'='*60}")
        else:
            print(f"\n{'='*60}")
            print(f"❌ 测试失败")
            print(f"{'='*60}")
    
    print(f"\n\n{'='*60}")
    print("测试完成!")
    print(f"{'='*60}\n")

if __name__ == "__main__":
    main()