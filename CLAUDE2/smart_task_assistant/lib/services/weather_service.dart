import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

/// 天气信息模型
class WeatherInfo {
  final String cityName;
  final double temperature;
  final String description;
  final String icon;
  final int humidity;
  final double windSpeed;

  WeatherInfo({
    required this.cityName,
    required this.temperature,
    required this.description,
    required this.icon,
    required this.humidity,
    required this.windSpeed,
  });

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
}

/// 天气服务 - 使用 OpenWeatherMap API
class WeatherService {
  // 使用免费的 OpenWeatherMap API
  static const String _apiKey = '4d8fb5b93d4af21d66a2948710284366';
  static const String _baseUrl =
      'https://api.openweathermap.org/data/2.5/weather';

  Position? _currentPosition;
  WeatherInfo? _currentWeather;

  /// 获取当前位置
  Future<Position?> getCurrentPosition() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return null;
      }

      _currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      return _currentPosition;
    } catch (e) {
      return null;
    }
  }

  /// 获取城市名称
  Future<String?> getCityName(Position position) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isNotEmpty) {
        return placemarks.first.locality ?? placemarks.first.administrativeArea;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// 获取天气信息
  Future<WeatherInfo?> getWeather() async {
    try {
      // 如果已有位置且天气信息，直接返回
      if (_currentWeather != null) {
        return _currentWeather;
      }

      // 获取当前位置
      _currentPosition = await getCurrentPosition();
      if (_currentPosition == null) {
        // 如果无法获取位置,使用默认城市(北京)
        return await _getWeatherByCity('Beijing');
      }

      // 使用经纬度获取天气
      return await _getWeatherByCoordinates(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
      );
    } catch (e) {
      // 如果出错,返回默认城市天气
      return await _getWeatherByCity('Beijing');
    }
  }

  /// 根据经纬度获取天气
  Future<WeatherInfo?> _getWeatherByCoordinates(double lat, double lon) async {
    try {
      final url =
          '$_baseUrl?lat=$lat&lon=$lon&appid=$_apiKey&units=metric&lang=zh_cn';
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _currentWeather = WeatherInfo.fromJson(data);
        return _currentWeather;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// 根据城市名称获取天气
  Future<WeatherInfo?> _getWeatherByCity(String cityName) async {
    try {
      final url =
          '$_baseUrl?q=$cityName&appid=$_apiKey&units=metric&lang=zh_cn';
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _currentWeather = WeatherInfo.fromJson(data);
        return _currentWeather;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// 清除缓存的天气信息
  void clearCache() {
    _currentWeather = null;
    _currentPosition = null;
  }
}
