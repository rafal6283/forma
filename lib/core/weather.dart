import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Pogoda teraz i na dziś (Open-Meteo, bez klucza).
class Weather {
  final String place;
  final double temp, wind; // °C, km/h
  final int code; // kod WMO
  final int rainChance; // % na dziś
  final double tMax;
  final DateTime at;
  const Weather(this.place, this.temp, this.wind, this.code, this.rainChance, this.tMax, this.at);

  bool get raining => code >= 51 && code != 45 && code != 48;

  /// Dobre warunki na trening na zewnątrz.
  bool get outdoorOk => !raining && rainChance < 40 && temp >= 6 && temp <= 28 && wind < 30;

  String get label => switch (code) {
        0 => 'słonecznie',
        1 || 2 => 'małe zachmurzenie',
        3 => 'pochmurno',
        45 || 48 => 'mgła',
        >= 51 && < 70 => 'deszcz',
        >= 71 && < 80 => 'śnieg',
        >= 80 && < 90 => 'przelotne opady',
        >= 95 => 'burza',
        _ => 'zmiennie',
      };

  String get icon => switch (code) {
        0 => '☀️',
        1 || 2 => '🌤',
        3 || 45 || 48 => '☁️',
        >= 71 && < 80 => '❄️',
        >= 95 => '⛈',
        >= 51 => '🌧',
        _ => '🌥',
      };

  /// Odczyt odpowiedzi Open-Meteo (testowalne bez sieci).
  static Weather? parse(String place, Map<String, Object?> j) {
    try {
      final cur = j['current'] as Map;
      final d = j['daily'] as Map;
      return Weather(
        place,
        (cur['temperature_2m'] as num).toDouble(),
        ((cur['wind_speed_10m'] as num?) ?? 0).toDouble(),
        (cur['weather_code'] as num).toInt(),
        (((d['precipitation_probability_max'] as List?)?.first as num?) ?? 0).toInt(),
        (((d['temperature_2m_max'] as List?)?.first as num?) ?? cur['temperature_2m'] as num).toDouble(),
        DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }
}

class WeatherService {
  WeatherService._();
  static final instance = WeatherService._();
  Weather? _cache;

  /// Pogoda dla miejscowości (wynik z pamięci przez 30 min). Null bez miejscowości lub sieci.
  Future<Weather?> now(String? city) async {
    if (city == null || city.trim().isEmpty) return null;
    if (_cache != null && _cache!.place == city && DateTime.now().difference(_cache!.at).inMinutes < 30) return _cache;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'geo.${city.trim().toLowerCase()}';
      var ll = prefs.getString(key);
      if (ll == null) {
        final g = await http
            .get(Uri.https('geocoding-api.open-meteo.com', '/v1/search',
                {'name': city.trim(), 'count': '1', 'language': 'pl', 'countryCode': 'PL'}))
            .timeout(const Duration(seconds: 8));
        final r = ((jsonDecode(g.body) as Map)['results'] as List?)?.cast<Map>();
        if (r == null || r.isEmpty) return null;
        ll = '${r.first['latitude']},${r.first['longitude']}';
        await prefs.setString(key, ll);
      }
      final p = ll.split(',');
      final f = await http
          .get(Uri.https('api.open-meteo.com', '/v1/forecast', {
            'latitude': p[0],
            'longitude': p[1],
            'current': 'temperature_2m,weather_code,wind_speed_10m',
            'daily': 'temperature_2m_max,precipitation_probability_max',
            'forecast_days': '1',
            'timezone': 'auto',
          }))
          .timeout(const Duration(seconds: 8));
      return _cache = Weather.parse(city, (jsonDecode(f.body) as Map).cast<String, Object?>());
    } catch (_) {
      return null;
    }
  }
}
