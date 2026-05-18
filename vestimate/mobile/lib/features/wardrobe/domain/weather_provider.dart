import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:vestimate/core/network/dio_provider.dart';

part 'weather_provider.g.dart';

class WeatherData {
  final String city;
  final int? tempCelsius;
  final String condition;
  final String emoji;
  final int? windKmh;
  final int? humidityPct;
  final bool available;

  const WeatherData({
    required this.city,
    required this.tempCelsius,
    required this.condition,
    required this.emoji,
    this.windKmh,
    this.humidityPct,
    required this.available,
  });

  factory WeatherData.fromJson(Map<String, dynamic> json) {
    return WeatherData(
      city: json['city'] as String? ?? '',
      tempCelsius: json['temp_celsius'] as int?,
      condition: json['condition'] as String? ?? 'unavailable',
      emoji: json['emoji'] as String? ?? '🌡',
      windKmh: json['wind_kmh'] as int?,
      humidityPct: json['humidity_pct'] as int?,
      available: json['available'] as bool? ?? false,
    );
  }

  /// Returns a display string like "22°C" or "--" if unavailable.
  String get tempDisplay =>
      tempCelsius != null ? '$tempCelsius°C' : '--';

  /// Single-line label: "☀️ 22°C · Clear Sky"
  String get shortLabel =>
      available ? '$emoji $tempDisplay' : '🌡 Unavailable';
}

@riverpod
Future<WeatherData> weather(WeatherRef ref) async {
  try {
    Position? position;
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceEnabled) {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
          position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.low);
        }
      }
    } catch (_) {
      // Gracefully ignore location errors (e.g. denied permanently)
    }

    final dio = ref.watch(dioProvider);
    final response = await dio.get(
      '/weather',
      queryParameters: {
        if (position != null) 'lat': position.latitude,
        if (position != null) 'lon': position.longitude,
      },
    );
    return WeatherData.fromJson(response.data as Map<String, dynamic>);
  } catch (_) {
    // Always return a degraded payload — never propagate error to UI
    return const WeatherData(
      city: '',
      tempCelsius: null,
      condition: 'unavailable',
      emoji: '🌡',
      available: false,
    );
  }
}
