import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;

import 'models.dart';
import 'store.dart';
import 'tcx.dart';

class StravaException implements Exception {
  final String message;
  StravaException(this.message);
  @override
  String toString() => message;
}

/// Strava: każda osoba łączy swoje konto; dane aplikacji API (Client ID/Secret) są wspólne dla telefonu.
///
/// Tryby po treningu:
/// - uzupełnienie aktywności, którą zegarek (np. Huawei → Strava) już wysłał: nazwa, rodzaj, lista ćwiczeń;
/// - nowa aktywność z pliku TCX (czas, kalorie, tętno z opaski);
/// - trening siłowy jako nowa aktywność z seriami (JSON): ćwiczenia, powtórzenia i mapa mięśni Stravy.
class Strava {
  Strava._();
  static final instance = Strava._();

  static const callbackScheme = 'forma';
  static const callbackDomain = 'forma.local';
  static const _redirect = '$callbackScheme://$callbackDomain';
  static const _api = 'https://www.strava.com/api/v3';
  final _ss = const FlutterSecureStorage();

  String get _tokKey => 'strava.tok.${Store.instance.userId}';

  // ------------------------------------------------------------ konfiguracja

  Future<(String, String)?> client() async {
    final raw = await _ss.read(key: 'strava.client');
    if (raw == null) return null;
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return (j['id'] as String, j['secret'] as String);
  }

  Future<void> setClient(String id, String secret) =>
      _ss.write(key: 'strava.client', value: jsonEncode({'id': id.trim(), 'secret': secret.trim()}));

  Future<Map<String, dynamic>?> _token() async {
    final raw = await _ss.read(key: _tokKey);
    return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
  }

  /// Nazwa połączonego konta albo null.
  Future<String?> athlete() async => (await _token())?['athlete'] as String?;

  Future<bool> connected() async => await _token() != null;

  // ------------------------------------------------------------ logowanie

  Future<String> connect() async {
    final c = await client();
    if (c == null) throw StravaException('Najpierw wpisz Client ID i Client Secret aplikacji Strava API.');
    final url = Uri.https('www.strava.com', '/oauth/mobile/authorize', {
      'client_id': c.$1,
      'redirect_uri': _redirect,
      'response_type': 'code',
      'approval_prompt': 'auto',
      'scope': 'read,activity:read_all,activity:write',
    });
    final result = await FlutterWebAuth2.authenticate(url: url.toString(), callbackUrlScheme: callbackScheme);
    final q = Uri.parse(result).queryParameters;
    if (q['error'] != null) throw StravaException('Strava odmówiła dostępu (${q['error']}).');
    final scope = q['scope'] ?? '';
    if (!scope.contains('activity:write')) {
      throw StravaException('Zaznacz w Stravie zgodę na tworzenie i edycję aktywności.');
    }
    final r = await http.post(Uri.parse('https://www.strava.com/oauth/token'), body: {
      'client_id': c.$1,
      'client_secret': c.$2,
      'code': q['code'] ?? '',
      'grant_type': 'authorization_code',
    });
    if (r.statusCode != 200) throw StravaException('Logowanie nieudane (${r.statusCode}): ${_err(r)}');
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    final a = (j['athlete'] as Map?)?.cast<String, dynamic>() ?? const {};
    final name = '${a['firstname'] ?? ''} ${a['lastname'] ?? ''}'.trim();
    await _saveToken(j, name);
    return name;
  }

  Future<void> _saveToken(Map<String, dynamic> j, String? athlete) async {
    final prev = await _token();
    await _ss.write(
      key: _tokKey,
      value: jsonEncode({
        'access': j['access_token'],
        'refresh': j['refresh_token'],
        'expires': j['expires_at'],
        'athlete': athlete ?? prev?['athlete'] ?? '',
      }),
    );
  }

  Future<void> disconnect() async {
    final t = await _token();
    if (t != null) {
      try {
        await http.post(Uri.parse('https://www.strava.com/oauth/deauthorize'),
            headers: {'Authorization': 'Bearer ${t['access']}'});
      } catch (_) {}
    }
    await _ss.delete(key: _tokKey);
  }

  Future<String> _access() async {
    final t = await _token();
    if (t == null) throw StravaException('Strava nie jest połączona.');
    final exp = (t['expires'] as num?)?.toInt() ?? 0;
    if (DateTime.now().millisecondsSinceEpoch ~/ 1000 < exp - 120) return t['access'] as String;
    final c = await client();
    if (c == null) throw StravaException('Brak danych aplikacji Strava API.');
    final r = await http.post(Uri.parse('https://www.strava.com/oauth/token'), body: {
      'client_id': c.$1,
      'client_secret': c.$2,
      'grant_type': 'refresh_token',
      'refresh_token': t['refresh'] as String,
    });
    if (r.statusCode != 200) throw StravaException('Nie udało się odświeżyć logowania (${r.statusCode}). Połącz ponownie.');
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    await _saveToken(j, null);
    return j['access_token'] as String;
  }

  static String _err(http.Response r) {
    try {
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      return (j['message'] ?? j['errors'] ?? r.body).toString();
    } catch (_) {
      return r.body.length > 200 ? r.body.substring(0, 200) : r.body;
    }
  }

  static String sportType(WorkoutKind k) => switch (k) {
        WorkoutKind.hiit => 'HighIntensityIntervalTraining',
        WorkoutKind.stretch => 'Yoga',
        WorkoutKind.mobility => 'Workout',
        _ => 'WeightTraining',
      };

  // ------------------------------------------------------------ wysyłka

  /// Aktywność z zegarka nachodząca na trening (null = brak).
  Future<Map<String, dynamic>?> findWatchActivity(Session s) async {
    final token = await _access();
    final after = s.start.subtract(const Duration(minutes: 45)).millisecondsSinceEpoch ~/ 1000;
    final before = s.end.add(const Duration(minutes: 30)).millisecondsSinceEpoch ~/ 1000;
    final r = await http.get(
      Uri.parse('$_api/athlete/activities?after=$after&before=$before&per_page=30'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (r.statusCode != 200) throw StravaException('Strava: ${r.statusCode} ${_err(r)}');
    final list = (jsonDecode(r.body) as List).cast<Map<String, dynamic>>();
    Map<String, dynamic>? best;
    var bestOverlap = 0;
    for (final a in list) {
      if ((a['external_id'] as String? ?? '').startsWith('forma-')) continue;
      final start = DateTime.tryParse(a['start_date'] as String? ?? '');
      final el = (a['elapsed_time'] as num?)?.toInt() ?? 0;
      if (start == null) continue;
      final end = start.add(Duration(seconds: el));
      final from = start.isAfter(s.start) ? start : s.start;
      final to = end.isBefore(s.end) ? end : s.end;
      final overlap = to.difference(from).inSeconds;
      // co najmniej połowa treningu musi się pokrywać
      if (overlap > s.duration.inSeconds * 0.5 && overlap > bestOverlap) {
        best = a;
        bestOverlap = overlap;
      }
    }
    return best;
  }

  Future<void> _update(int id, Session s, {bool rename = true}) async {
    final token = await _access();
    final r = await http.put(
      Uri.parse('$_api/activities/$id'),
      headers: {'Authorization': 'Bearer $token'},
      body: {
        if (rename) 'name': '${s.title} · Forma',
        'sport_type': sportType(s.kind),
        'description': sessionDescription(s),
      },
    );
    if (r.statusCode != 200) throw StravaException('Nie udało się uzupełnić aktywności (${r.statusCode}): ${_err(r)}');
  }

  /// Nowa aktywność z pliku TCX (z tętnem z opaski, jeśli było).
  Future<int> upload(Session s) => _uploadFile(s, 'tcx', sessionTcx(s), {});

  /// Nowa aktywność z seriami (JSON): Strava pokaże ćwiczenia, powtórzenia i mapę mięśni.
  Future<int> uploadSets(Session s) =>
      _uploadFile(s, 'json', sessionSetsJson(s), {'sport_type': setsSportType(s.kind)!}, ext: 'json');

  Future<int> _uploadFile(Session s, String type, String content, Map<String, String> extra, {String? ext}) async {
    final token = await _access();
    final req = http.MultipartRequest('POST', Uri.parse('$_api/uploads'))
      ..headers['Authorization'] = 'Bearer $token'
      ..fields.addAll({
        'data_type': type,
        'name': '${s.title} · Forma',
        'description': sessionDescription(s),
        'trainer': '1',
        'external_id': 'forma-${s.id}${type == 'json' ? '-sets' : ''}',
        ...extra,
      })
      ..files.add(http.MultipartFile.fromString('file', content, filename: 'forma-${s.id}.${ext ?? type}'));
    final res = await http.Response.fromStream(await req.send());
    if (res.statusCode != 201 && res.statusCode != 200) {
      throw StravaException('Wysyłka nieudana (${res.statusCode}): ${_err(res)}');
    }
    final up = jsonDecode(res.body) as Map<String, dynamic>;
    final upId = up['id'];
    for (var i = 0; i < 20; i++) {
      await Future.delayed(Duration(seconds: i < 5 ? 1 : 2));
      final r = await http.get(Uri.parse('$_api/uploads/$upId'), headers: {'Authorization': 'Bearer $token'});
      if (r.statusCode != 200) continue;
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      if (j['error'] != null) {
        final err = j['error'].toString();
        // duplikat — aktywność już jest
        final m = RegExp(r'activities/(\d+)').firstMatch(err);
        if (m != null) return int.parse(m.group(1)!);
        throw StravaException('Strava odrzuciła plik: $err');
      }
      final aid = (j['activity_id'] as num?)?.toInt();
      if (aid != null) {
        if (type != 'json') {
          try {
            await _update(aid, s, rename: false);
          } catch (e) {
            debugPrint('Strava: rodzaj aktywności: $e');
          }
        }
        return aid;
      }
    }
    throw StravaException('Strava jeszcze przetwarza plik — sprawdź za chwilę w aplikacji Strava.');
  }

  /// Po treningu: uzupełnij aktywność z zegarka albo wyślij nową. Zwraca opis wyniku.
  Future<String> push(Session s, {bool forceUpload = false}) async {
    final p = Store.instance.profile;
    // trening siłowy z seriami → nowa aktywność z ćwiczeniami i mapą mięśni
    if (p.stravaSets && setsSportType(s.kind) != null && s.done.isNotEmpty) {
      try {
        final id = await uploadSets(s);
        s.stravaId = id;
        s.stravaPending = false;
        await Store.instance.save();
        return 'Wysłano trening do Stravy z seriami i mapą mięśni';
      } on StravaException catch (e) {
        // np. konto bez dostępu do formatu serii — dalej jak dotąd (opis + tętno)
        debugPrint('Strava serie: $e');
      }
    }
    if (!forceUpload && p.stravaMatch) {
      final a = await findWatchActivity(s);
      if (a != null) {
        final id = (a['id'] as num).toInt();
        await _update(id, s);
        s.stravaId = id;
        s.stravaPending = false;
        await Store.instance.save();
        return 'Uzupełniono aktywność „${a['name']}” w Stravie';
      }
      // zegarek mógł jeszcze nie zsynchronizować — spróbujemy później
      if (DateTime.now().difference(s.end).inHours < 24) {
        s.stravaPending = true;
        await Store.instance.save();
        return 'Czekam, aż aktywność z zegarka trafi do Stravy — uzupełnię ją automatycznie';
      }
    }
    final id = await upload(s);
    s.stravaId = id;
    s.stravaPending = false;
    await Store.instance.save();
    return 'Wysłano trening do Stravy';
  }

  /// Ponowne próby dla treningów czekających na aktywność z zegarka (przy otwarciu aplikacji).
  Future<void> retryPending() async {
    if (!await connected()) return;
    for (final s in Store.instance.sessions.where((x) => x.stravaPending && x.stravaId == null).toList()) {
      try {
        final a = await findWatchActivity(s);
        if (a != null) {
          final id = (a['id'] as num).toInt();
          await _update(id, s);
          s.stravaId = id;
          s.stravaPending = false;
        } else if (DateTime.now().difference(s.end).inHours >= 24) {
          s.stravaPending = false; // przestajemy czekać; można wysłać ręcznie
        }
      } catch (e) {
        debugPrint('Strava retry: $e');
      }
    }
    await Store.instance.save();
  }
}
