import 'package:shared_preferences/shared_preferences.dart';

import 'health_sync.dart';
import 'models.dart';
import 'store.dart';
import 'strava.dart';

/// Aktywności z zewnątrz pokrywające się z treningiem Formy (np. ten sam trening nagrany zegarkiem) pomijamy.
bool overlapsForma(ExternalActivity a, List<Session> sessions) {
  final end = a.start.add(Duration(minutes: a.minutes));
  for (final s in sessions) {
    if (s.stravaId != null && a.id == 'strava:${s.stravaId}') return true;
    final from = a.start.isAfter(s.start) ? a.start : s.start;
    final to = end.isBefore(s.end) ? end : s.end;
    final ov = to.difference(from).inSeconds;
    if (ov > 0 && ov >= 0.5 * a.minutes * 60) return true;
  }
  return false;
}

/// Import biegów, rowerów i innych aktywności ze Stravy i Health Connect — liczą się do obciążenia i serii.
class ActivityImport {
  ActivityImport._();
  static final instance = ActivityImport._();

  String get _key => 'import.last.${Store.instance.userId}';

  /// Zwraca (nowe, błąd). Pierwszy import sięga 6 tygodni wstecz.
  Future<(int, String?)> run({bool strava = true, bool health = true}) async {
    final store = Store.instance;
    final prefs = await SharedPreferences.getInstance();
    final last = DateTime.tryParse(prefs.getString(_key) ?? '');
    final from = (last ?? DateTime.now().subtract(const Duration(days: 42))).subtract(const Duration(days: 2));
    final found = <ExternalActivity>[];
    final errors = <String>[];
    if (strava && await Strava.instance.connected()) {
      try {
        found.addAll(await Strava.instance.activities(from));
      } catch (e) {
        errors.add('Strava: $e');
      }
    }
    if (health && store.profile.healthConnect) {
      try {
        found.addAll(await HealthSync.instance.workouts(from));
      } catch (e) {
        errors.add('Health Connect: $e');
      }
    }
    // ta sama aktywność z dwóch źródeł: zostaje pierwsza (Strava ma nazwę i tętno)
    final unique = <ExternalActivity>[];
    for (final a in found) {
      if (overlapsForma(a, store.sessions)) continue;
      final dup = unique.any((u) => (u.start.difference(a.start).inMinutes).abs() < 10 && (u.minutes - a.minutes).abs() < 10);
      if (!dup && !store.external.any((u) => u.id != a.id && (u.start.difference(a.start).inMinutes).abs() < 10 && (u.minutes - a.minutes).abs() < 10)) {
        unique.add(a);
      }
    }
    final n = await store.addExternal(unique);
    if (errors.isEmpty) await prefs.setString(_key, DateTime.now().toIso8601String());
    return (n, errors.isEmpty ? null : errors.join('\n'));
  }
}
