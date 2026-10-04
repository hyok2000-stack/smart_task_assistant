import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/city.dart';

/// 天气信息模型
class WeatherInfo {
  final String cityName;
  final double temperature;
  final String description;
  final String icon;
  final int humidity;
  final double windSpeed;
  final DateTime fetchedAt;

  WeatherInfo({
    required this.cityName,
    required this.temperature,
    required this.description,
    required this.icon,
    required this.humidity,
    required this.windSpeed,
    DateTime? fetchedAt,
  }) : fetchedAt = fetchedAt ?? DateTime.now();

  factory WeatherInfo.fromJson(Map<String, dynamic> json) {
    return WeatherInfo(
      cityName: json['location']?['name'] ??
          json['basic']?['location']?[0]?['name'] ??
          '未知',
      temperature: (json['now']?['temp'] as num?)?.toDouble() ?? 20.0,
      description: json['now']?['text'] ?? '暂无数据',
      icon: json['now']?['icon'] ?? '100',
      humidity: json['now']?['humidity'] ?? 0,
      windSpeed: (json['now']?['windSpeed'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// 获取温度描述
  String get temperatureText => '${temperature.round()}°C';

  /// 转换为JSON（用于缓存）
  Map<String, dynamic> toJson() {
    return {
      'cityName': cityName,
      'temperature': temperature,
      'description': description,
      'icon': icon,
      'humidity': humidity,
      'windSpeed': windSpeed,
      'fetchedAt': fetchedAt.toIso8601String(),
    };
  }

  /// 从JSON创建（用于缓存）
  factory WeatherInfo.fromCacheJson(Map<String, dynamic> json) {
    return WeatherInfo(
      cityName: json['cityName'],
      temperature: json['temperature'].toDouble(),
      description: json['description'],
      icon: json['icon'],
      humidity: json['humidity'],
      windSpeed: json['windSpeed'].toDouble(),
      fetchedAt: DateTime.parse(json['fetchedAt']),
    );
  }

  /// 检查缓存是否过期（30分钟）
  bool get isExpired {
    return DateTime.now().difference(fetchedAt).inMinutes > 30;
  }
}

/// 天气服务 - 使用高德地图天气API
///
/// 优化特性：
/// 1. 请求超时控制（3秒）
/// 2. 自动重试机制（最多3次）
/// 3. 本地缓存（30分钟有效期）
/// 4. 优雅降级（失败时使用缓存或默认城市）
/// 5. 模拟数据支持（API不可用时）
class WeatherService {
  // 使用高德地图天气API
  static const String _apiKey = '2ed8821a151fad7c1f9a512e400bf19d';
  static const String _baseUrl =
      'https://restapi.amap.com/v3/weather/weatherInfo';
  // 高德 IP 定位 API（不需要 Google Play Services，不依赖原生插件）
  static const String _ipLocateUrl = 'https://restapi.amap.com/v3/ip';

  // 城市名称到高德adcode的映射
  static const Map<String, String> _cityAdcodes = {
    '北京': '110101',
    '东城区': '110101',
    '上海': '310101',
    '黄浦区': '310101',
    '广州': '440100',
    '深圳': '440304',
    '福田区': '440304',
    '杭州': '330100',
    '成都': '510100',
    '武汉': '420100',
    '西安': '610100',
  };

  // 是否使用模拟数据（API不可用时自动切换）
  bool _useMockData = false;
  final String _mockDataMessage = '使用模拟数据（API不可用）';

  // 配置常量
  static const Duration _timeout = Duration(seconds: 3);
  static const int _maxRetries = 3;
  static const String _cacheKey = 'weather_cache';
  static const String _selectedCityKey = 'selected_city';

  // IP 定位结果缓存（城市名 + adcode），替代原 Geolocator 的 Position
  String? _locatedCity;
  WeatherInfo? _currentWeather;
  bool _isLoading = false;
  CityInfo? _selectedCity; // 用户选择的城市

  /// 获取模拟天气数据
  WeatherInfo _getMockWeather(String cityName) {
    debugPrint('天气服务：$_mockDataMessage - $cityName');

    // 模拟数据字典
    final mockData = {
      '北京': {
        'temperature': 18.0,
        'description': '晴',
        'humidity': 45,
        'windSpeed': 3.2,
      },
      '上海': {
        'temperature': 22.0,
        'description': '多云',
        'humidity': 60,
        'windSpeed': 4.1,
      },
      '广州': {
        'temperature': 28.0,
        'description': '阴',
        'humidity': 75,
        'windSpeed': 2.8,
      },
      '深圳': {
        'temperature': 27.0,
        'description': '小雨',
        'humidity': 80,
        'windSpeed': 3.5,
      },
      '杭州': {
        'temperature': 20.0,
        'description': '晴转多云',
        'humidity': 55,
        'windSpeed': 3.0,
      },
      '成都': {
        'temperature': 19.0,
        'description': '多云',
        'humidity': 65,
        'windSpeed': 2.5,
      },
      '武汉': {
        'temperature': 21.0,
        'description': '阴',
        'humidity': 70,
        'windSpeed': 3.8,
      },
      '西安': {
        'temperature': 17.0,
        'description': '晴',
        'humidity': 40,
        'windSpeed': 4.0,
      },
    };

    // 获取城市数据，如果没有则使用默认
    final cityData = mockData[cityName] ??
        {
          'temperature': 20.0,
          'description': '晴',
          'humidity': 50,
          'windSpeed': 3.5,
        };

    return WeatherInfo(
      cityName: cityName,
      temperature: (cityData['temperature'] as num).toDouble(),
      description: cityData['description'] as String,
      icon: '100',
      humidity: (cityData['humidity'] as num).toInt(),
      windSpeed: (cityData['windSpeed'] as num).toDouble(),
    );
  }

  /// 获取天气信息（带缓存）
  Future<WeatherInfo?> getWeather({bool forceRefresh = false}) async {
    try {
      // 如果正在加载，等待加载完成
      if (_isLoading && !forceRefresh) {
        debugPrint('天气服务：正在加载中，等待加载完成');
        // 等待最多5秒
        int waitCount = 0;
        while (_isLoading && waitCount < 50) {
          await Future.delayed(const Duration(milliseconds: 100));
          waitCount++;
        }
        if (_currentWeather != null) {
          debugPrint('天气服务：等待后返回缓存的天气');
          return _currentWeather;
        }
      }

      // 强制刷新时跳过缓存检查
      if (!forceRefresh) {
        // 检查内存缓存
        if (_currentWeather != null && !_currentWeather!.isExpired) {
          debugPrint(
              '天气服务：使用内存缓存（${_currentWeather!.cityName}, ${_currentWeather!.temperatureText}）');
          return _currentWeather;
        }
      }

      // 检查本地缓存
      final cachedWeather = await _loadFromCache();
      if (cachedWeather != null && !cachedWeather.isExpired) {
        debugPrint(
            '天气服务：使用本地缓存（${cachedWeather.cityName}, ${cachedWeather.temperatureText}）');
        _currentWeather = cachedWeather;
        return cachedWeather;
      }

      // 只有在没有已选择的城市时才加载用户选择的城市
      // 这样可以避免在setSelectedCity后立即调用getWeather时被覆盖
      if (_selectedCity == null) {
        await _loadSelectedCity();
        debugPrint('天气服务：从SharedPreferences加载城市 - ${_selectedCity?.name}');
      } else {
        debugPrint('天气服务：使用已设置的城市 - ${_selectedCity?.name}');
      }

      // 需要重新获取
      _isLoading = true;
      debugPrint('天气服务：开始获取新天气数据...');
      debugPrint('天气服务：当前选择的城市 - ${_selectedCity?.name ?? "无"}');

      WeatherInfo? weather;

      // 优先使用用户选择的城市
      if (_selectedCity != null) {
        debugPrint('天气服务：使用用户选择的城市（${_selectedCity!.name}）获取天气');
        weather = await _getWeatherWithRetry(
          () => _getWeatherByCity(_selectedCity!.name),
        );
      } else {
        // 如果用户没有选择城市，尝试使用 IP 定位获取天气
        debugPrint('天气服务：用户未选择城市，尝试使用 IP 定位获取天气');
        await _locateByIp();
        if (_locatedCity != null) {
          debugPrint('天气服务：IP 定位成功 - $_locatedCity');
          weather = await _getWeatherWithRetry(
            () => _getWeatherByCity(_locatedCity!),
          );
        }

        // 如果 IP 定位失败，使用默认城市（北京）
        if (weather == null) {
          debugPrint('天气服务：IP 定位失败，使用默认城市（北京）获取天气');
          weather = await _getWeatherWithRetry(
            () => _getWeatherByCity('北京'),
          );
        }
      }

      _isLoading = false;

      // 缓存成功获取的天气
      if (weather != null) {
        _currentWeather = weather;
        await _saveToCache(weather);
        debugPrint(
            '天气服务：获取成功（${weather.cityName}, ${weather.temperatureText}, ${weather.description}）');
      } else {
        // 如果API获取失败，切换到模拟数据模式
        if (!_useMockData) {
          _useMockData = true;
          debugPrint('天气服务：API不可用，自动切换到模拟数据模式');
        }

        // 获取城市名称
        final cityName = _selectedCity?.name ?? '北京';
        weather = _getMockWeather(cityName);

        // 缓存模拟数据
        _currentWeather = weather;
        await _saveToCache(weather);
        debugPrint(
            '天气服务：使用模拟数据（${weather.cityName}, ${weather.temperatureText}）');
      }

      return _currentWeather;
    } catch (e) {
      debugPrint('天气服务：发生异常 - $e');
      _isLoading = false;

      // 异常时切换到模拟数据
      if (!_useMockData) {
        _useMockData = true;
        debugPrint('天气服务：发生异常，切换到模拟数据模式');
      }

      final cityName = _selectedCity?.name ?? '北京';
      final weather = _getMockWeather(cityName);

      // 缓存模拟数据
      _currentWeather = weather;
      await _saveToCache(weather);

      return weather;
    }
  }

  /// 获取当前位置（带超时）
  /// 通过高德 IP 定位 API 获取城市信息（纯 HTTP，不需要 Google Play Services，
  /// 不依赖 geolocator 原生插件，在华为等无 GMS 设备上也不会崩溃）。
  Future<void> _locateByIp() async {
    try {
      const url = '$_ipLocateUrl?key=$_apiKey';
      debugPrint('天气服务：请求 IP 定位...');
      final response = await http.get(Uri.parse(url)).timeout(_timeout);

      if (response.statusCode != 200) {
        debugPrint('天气服务：IP 定位 HTTP 错误 - ${response.statusCode}');
        return;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final status = data['status']?.toString();
      if (status != '1') {
        debugPrint('天气服务：IP 定位失败 - ${data['info']}');
        return;
      }

      final city = data['city'] as String?;
      final adcode = data['adcode'] as String?;
      if (city != null && city.isNotEmpty) {
        _locatedCity = city;
        debugPrint('天气服务：IP 定位成功 - 城市: $city, adcode: $adcode');
      }
    } catch (e) {
      debugPrint('天气服务：IP 定位异常 - $e');
    }
  }

  /// 带重试机制的网络请求
  Future<WeatherInfo?> _getWeatherWithRetry(
    Future<WeatherInfo?> Function() request,
  ) async {
    for (int i = 0; i < _maxRetries; i++) {
      try {
        final result = await request().timeout(_timeout, onTimeout: () {
          debugPrint('天气服务：请求超时（第${i + 1}次尝试）');
          return Future.value(null);
        });

        if (result != null) {
          return result;
        }

        // 如果失败但还有重试机会，等待后重试
        if (i < _maxRetries - 1) {
          await Future.delayed(Duration(milliseconds: 500 * (i + 1)));
        }
      } catch (e) {
        debugPrint('天气服务：请求失败（第${i + 1}次尝试）- $e');

        if (i < _maxRetries - 1) {
          await Future.delayed(Duration(milliseconds: 500 * (i + 1)));
        }
      }
    }

    debugPrint('天气服务：已达到最大重试次数（$_maxRetries次）');
    return null;
  }

  /// 根据城市名称获取天气（高德地图API）
  Future<WeatherInfo?> _getWeatherByCity(String cityName) async {
    try {
      // 标准化城市名称（去掉"市"、"区"等后缀）
      String normalizedCityName = cityName
          .replaceAll('市', '')
          .replaceAll('区', '')
          .replaceAll('省', '')
          .trim();

      debugPrint('天气服务：查询城市 - $cityName (标准化: $normalizedCityName)');

      // 获取城市adcode（尝试标准化的名称）
      String? adcode = _cityAdcodes[normalizedCityName];

      // 如果没有找到，尝试原始名称
      adcode ??= _cityAdcodes[cityName];

      // 如果还没有找到，尝试使用城市名作为adcode
      if (adcode == null) {
        debugPrint('天气服务：未找到城市$cityName的adcode，尝试使用城市名');
        adcode = normalizedCityName;
      }

      debugPrint('天气服务：使用adcode - $adcode');

      // 构建请求URL
      final url = Uri.parse(_baseUrl).replace(
        queryParameters: {
          'city': adcode,
          'key': _apiKey,
          'extensions': 'base',
        },
      );

      debugPrint('天气服务：请求URL - $url');

      final response = await http.get(url).timeout(_timeout);
      debugPrint('天气服务：响应状态码 - ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // 高德API返回格式检查
        if (data['status'] == '1' && data['lives'] != null) {
          final lives = data['lives'];
          if (lives is List && lives.isNotEmpty) {
            final live = lives[0];
            if (live is Map) {
              // 解析高德天气数据
              final temperature =
                  double.tryParse(live['temperature']?.toString() ?? '0') ?? 0;
              final humidity =
                  int.tryParse(live['humidity']?.toString() ?? '0') ?? 0;
              final windPower = live['windpower']?.toString() ?? '未知';

              // 获取API返回的城市名称，优先使用用户选择的城市名称
              String displayCityName = live['city'] ?? cityName;

              // 如果API返回的是区名，使用用户选择的城市名称
              if (displayCityName.contains('区') ||
                  displayCityName.contains('县')) {
                displayCityName = cityName;
              }

              // 转换风力为数值（简化处理）
              double windSpeed = 3.0;
              if (windPower.contains('≤3')) {
                windSpeed = 2.0;
              } else if (windPower.contains('3-4')) {
                windSpeed = 3.5;
              } else if (windPower.contains('4-5')) {
                windSpeed = 4.5;
              }

              final weather = WeatherInfo(
                cityName: displayCityName,
                temperature: temperature,
                description: live['weather'] ?? '暂无数据',
                icon: '100',
                humidity: humidity,
                windSpeed: windSpeed,
              );

              debugPrint(
                  '天气服务：解析成功 - ${weather.cityName}, ${weather.temperatureText}, ${weather.description}');
              return weather;
            }
          }
        }

        debugPrint(
            '天气服务：API返回错误 - status=${data['status']}, info=${data['info']}');
        return null;
      } else {
        debugPrint('天气服务：HTTP错误 - ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('天气服务：网络请求异常 - $e');
      return null;
    }
  }

  /// 保存到本地缓存
  Future<void> _saveToCache(WeatherInfo weather) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, json.encode(weather.toJson()));
      debugPrint('天气服务：已保存到本地缓存');
    } catch (e) {
      debugPrint('天气服务：保存缓存失败 - $e');
    }
  }

  /// 从本地缓存加载
  Future<WeatherInfo?> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheString = prefs.getString(_cacheKey);

      if (cacheString != null) {
        final cacheData = json.decode(cacheString);
        final weather = WeatherInfo.fromCacheJson(cacheData);
        debugPrint('天气服务：从本地缓存加载成功');
        return weather;
      }

      return null;
    } catch (e) {
      debugPrint('天气服务：加载缓存失败 - $e');
      return null;
    }
  }

  /// 清除缓存
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
      _currentWeather = null;
      _locatedCity = null;
      debugPrint('天气服务：已清除缓存');
    } catch (e) {
      debugPrint('天气服务：清除缓存失败 - $e');
    }
  }

  /// 刷新天气（强制重新获取）
  Future<WeatherInfo?> refreshWeather() async {
    debugPrint('天气服务：强制刷新天气');
    _currentWeather = null;
    return await getWeather(forceRefresh: true);
  }

  /// 加载用户选择的城市
  Future<void> _loadSelectedCity() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cityString = prefs.getString(_selectedCityKey);
      if (cityString != null) {
        final cityData = json.decode(cityString);
        _selectedCity = CityInfo.fromJson(cityData);
        debugPrint('天气服务：已加载用户选择的城市 - ${_selectedCity!.name}');
      }
    } catch (e) {
      debugPrint('天气服务：加载城市选择失败 - $e');
    }
  }

  /// 设置用户选择的城市
  Future<WeatherInfo?> setSelectedCity(CityInfo? city) async {
    try {
      _selectedCity = city;

      // 确保清除所有缓存
      _currentWeather = null;

      // 也清除本地缓存
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);

      if (city != null) {
        await prefs.setString(_selectedCityKey, json.encode(city.toJson()));
      } else {
        await prefs.remove(_selectedCityKey);
      }

      // 强制刷新天气，跳过缓存
      final weather = await getWeather(forceRefresh: true);
      return weather;
    } catch (e) {
      debugPrint('天气服务：保存城市选择失败 - $e');
      return null;
    }
  }

  /// 获取当前选择的城市
  CityInfo? get selectedCity => _selectedCity;
}
