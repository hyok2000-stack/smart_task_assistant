#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
测试高德地图天气API
"""
import requests
import json

# 高德API密钥
API_KEY = "2ed8821a151fad7c1f9a512e400bf19d"
# 高德天气API地址
BASE_URL = "https://restapi.amap.com/v3/weather/weatherInfo"

# 常用城市编码（高德Adcode）
CITY_CODES = {
    '北京': '110101',
    '上海': '310101',
    '广州': '440101',
    '深圳': '440304',
    '杭州': '330101',
    '成都': '510101',
    '武汉': '420100',
    '西安': '610101',
}

def test_weather_by_city(city_name, city_code):
    """测试城市天气"""
    print(f"\n{'='*60}")
    print(f"测试城市: {city_name} (编码: {city_code})")
    print(f"{'='*60}")
    
    url = BASE_URL
    params = {
        'city': city_code,
        'key': API_KEY,
        'extensions': 'base'  # base: 实时天气, all: 预报天气
    }
    
    try:
        response = requests.get(url, params=params, timeout=10)
        print(f"请求URL: {response.url}")
        print(f"状态码: {response.status_code}")
        
        if response.status_code == 200:
            data = response.json()
            print(f"\n完整响应:\n{json.dumps(data, ensure_ascii=False, indent=2)}")
            
            # 检查返回状态
            if data.get('status') == '1' and data.get('lives'):
                lives = data['lives']
                if len(lives) > 0:
                    live = lives[0]
                    print(f"\n✅ 天气数据获取成功:")
                    print(f"   省份: {live.get('province')}")
                    print(f"   城市: {live.get('city')}")
                    print(f"   温度: {live.get('temperature')}°C")
                    print(f"   天气: {live.get('weather')}")
                    print(f"   风向: {live.get('winddirection')}")
                    print(f"   风力: {live.get('windpower')}级")
                    print(f"   湿度: {live.get('humidity')}%")
                    print(f"   更新时间: {live.get('reporttime')}")
                    return True
            else:
                print(f"\n❌ API返回错误: status={data.get('status')}, info={data.get('info')}")
                return False
        else:
            print(f"\n❌ HTTP错误: {response.status_code}")
            return False
    except Exception as e:
        print(f"\n❌ 请求异常: {e}")
        return False

def main():
    print("\n" + "="*60)
    print("高德地图天气API测试工具")
    print("="*60)
    
    success_count = 0
    total_count = len(CITY_CODES)
    
    for city_name, city_code in CITY_CODES.items():
        if test_weather_by_city(city_name, city_code):
            success_count += 1
            print(f"\n{'='*60}")
            print(f"✅ {city_name} 测试成功!")
            print(f"{'='*60}")
        else:
            print(f"\n{'='*60}")
            print(f"❌ {city_name} 测试失败")
            print(f"{'='*60}")
    
    print(f"\n\n{'='*60}")
    print(f"测试完成! 成功: {success_count}/{total_count}")
    print(f"{'='*60}\n")
    
    if success_count == total_count:
        print("✅ 所有城市测试通过，高德API可用！")
        return True
    else:
        print(f"❌ 有 {total_count - success_count} 个城市测试失败")
        return False

if __name__ == "__main__":
    success = main()
    exit(0 if success else 1)