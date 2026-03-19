import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      cityName: json['name'] ?? '未知',
      temperature: (json['main']['temp'] as num).toDouble(),
      description: json['weather'][0]['description'] ?? '',
      icon: json['weather'][0]['icon'] ?? '',
      humidity: json['main']['humidity'] ?? 0,
      windSpeed: (json['wind']['speed'] as num).toDouble(),
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

/// 天气服务 - 使用 OpenWeatherMap API
///
/// 优化特性：
/// 1. 请求超时控制（3秒）
/// 2. 自动重试机制（最多3次）
/// 3. 本地缓存（30分钟有效期）
/// 4. 优雅降级（失败时使用缓存或默认城市）
class WeatherService {
  // 使用免费的 OpenWeatherMap API
  static const String _apiKey = '4d8fb5b93d4af21d66a2948710284366';
  static const String _baseUrl =
      'https://api.openweathermap.org/data/2.5/weather';

  // 配置常量
  static const Duration _timeout = Duration(seconds: 3);
  static const int _maxRetries = 3;
  static const String _cacheKey = 'weather_cache';

  Position? _currentPosition;
  WeatherInfo? _currentWeather;
  bool _isLoading = false;

  /// 获取天气信息（带缓存）
  Future<WeatherInfo?> getWeather() async {
    try {
      // 如果正在加载，直接返回缓存的天气（如果有）
      if (_isLoading && _currentWeather != null) {
        debugPrint('天气服务：正在加载中，返回缓存数据');
        return _currentWeather;
      }

      // 检查内存缓存
      if (_currentWeather != null && !_currentWeather!.isExpired) {
        debugPrint(
            '天气服务：使用内存缓存（${_currentWeather!.cityName}, ${_currentWeather!.temperatureText}）');
        return _currentWeather;
      }

      // 检查本地缓存
      final cachedWeather = await _loadFromCache();
      if (cachedWeather != null && !cachedWeather.isExpired) {
        debugPrint(
            '天气服务：使用本地缓存（${cachedWeather.cityName}, ${cachedWeather.temperatureText}）');
        _currentWeather = cachedWeather;
        return cachedWeather;
      }

      // 需要重新获取
      _isLoading = true;
      debugPrint('天气服务：开始获取新天气数据...');

      WeatherInfo? weather;

      // 尝试使用位置获取天气
      _currentPosition = await _getCurrentPositionWithTimeout();
      if (_currentPosition != null) {
        debugPrint('天气服务：使用位置获取天气');
        weather = await _getWeatherWithRetry(
          () => _getWeatherByCoordinates(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
          ),
        );
      }

      // 如果位置获取失败，使用默认城市
      if (weather == null) {
        debugPrint('天气服务：使用默认城市（北京）获取天气');
        weather = await _getWeatherWithRetry(
          () => _getWeatherByCity('Beijing'),
        );
      }

      _isLoading = false;

      // 缓存成功获取的天气
      if (weather != null) {
        _currentWeather = weather;
        await _saveToCache(weather);
        debugPrint(
            '天气服务：获取成功（${weather.cityName}, ${weather.temperatureText}, ${weather.description}）');
      } else {
        // 如果都失败了，返回过期的缓存（如果有）
        if (cachedWeather != null) {
          debugPrint('天气服务：获取失败，返回过期缓存');
          _currentWeather = cachedWeather;
          return cachedWeather;
        }
        // 返回默认天气信息
        debugPrint('天气服务：获取失败，返回默认信息');
        _currentWeather = WeatherInfo(
          cityName: '未知',
          temperature: 20,
          description: '暂无数据',
          icon: '',
          humidity: 50,
          windSpeed: 3.5,
        );
      }

      return _currentWeather;
    } catch (e) {
      debugPrint('天气服务：发生异常 - $e');
      _isLoading = false;

      // 异常时返回缓存的天气（即使过期）
      if (_currentWeather != null) {
        return _currentWeather;
      }

      // 返回默认天气
      return WeatherInfo(
        cityName: '未知',
        temperature: 20,
        description: '暂无数据',
        icon: '',
        humidity: 50,
        windSpeed: 3.5,
      );
    }
  }

  /// 获取当前位置（带超时）
  Future<Position?> _getCurrentPositionWithTimeout() async {
    try {
      // 使用超时控制位置获取
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: _timeout,
      ).timeout(_timeout, onTimeout: () {
        debugPrint('天气服务：获取位置超时');
        return Future.value(null);
      });
    } catch (e) {
      debugPrint('天气服务：获取位置失败 - $e');
      return null;
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

  /// 根据经纬度获取天气
  Future<WeatherInfo?> _getWeatherByCoordinates(double lat, double lon) async {
    try {
      final url =
          '$_baseUrl?lat=$lat&lon=$lon&appid=$_apiKey&units=metric&lang=zh_cn';
      debugPrint('天气服务：请求URL - $url');

      final response = await http.get(Uri.parse(url)).timeout(_timeout);
      debugPrint('天气服务：响应状态码 - ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final weather = WeatherInfo.fromJson(data);
        debugPrint('天气服务：解析成功 - ${weather.cityName}');
        return weather;
      } else {
        debugPrint('天气服务：HTTP错误 - ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('天气服务：网络请求异常 - $e');
      return null;
    }
  }

  /// 根据城市名称获取天气
  Future<WeatherInfo?> _getWeatherByCity(String cityName) async {
    try {
      final url =
          '$_baseUrl?q=$cityName&appid=$_apiKey&units=metric&lang=zh_cn';
      debugPrint('天气服务：请求URL - $url');

      final response = await http.get(Uri.parse(url)).timeout(_timeout);
      debugPrint('天气服务：响应状态码 - ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final weather = WeatherInfo.fromJson(data);
        debugPrint('天气服务：解析成功 - ${weather.cityName}');
        return weather;
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
      _currentPosition = null;
      debugPrint('天气服务：已清除缓存');
    } catch (e) {
      debugPrint('天气服务：清除缓存失败 - $e');
    }
  }

  /// 刷新天气（强制重新获取）
  Future<WeatherInfo?> refreshWeather() async {
    debugPrint('天气服务：强制刷新天气');
    _currentWeather = null;
    return await getWeather();
  }
}
