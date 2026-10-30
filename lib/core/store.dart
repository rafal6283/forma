import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// Statystyki ćwiczenia: ile razy, kiedy ostatnio i jak oceniane.
class ExStat {
  int count;
  DateTime? last;
  int score; // suma ocen: -1 za łatwe, +1 za trudne
  bool favorite;
  bool hidden;

  ExStat({this.count = 0, this.last, this.score = 0, this.favorite = false, this.hidden = false});

  Map<String, dynamic> toJson() =>
      {'c': count, 'l': last?.toIso8601String(), 's': score, 'f': favorite, 'h': hidden};

  factory ExStat.fromJson(Map<String, dynamic> j) => ExStat(
        count: (j['c'] as num?)?.toInt() ?? 0,
        last: j['l'] == null ? null : DateTime.tryParse(j['l'] as String),
        score: (j['s'] as num?)?.toInt() ?? 0,
        favorite: j['f'] == true,
        hidden: j['h'] == true,
      );
}

/// Wszystkie dane aplikacji w jednym pliku JSON.
class Store extends ChangeNotifier {
  Store._();
  static final instance = Store._();

  Profile profile = Profile();
  final List<Session> sessions = [];
  final List<CheckIn> checkins = [];
  final List<HrvMeasure> hrv = [];
  final Map<String, ExStat> stats = {};
  HealthSnapshot health = HealthSnapshot.empty;

  File? _file;

  Future<void> load() async {
    final dir = await getApplicationDocumentsDirectory();
    _file = File('${dir.path}/forma.json');
    if (await _file!.exists()) {
      try {
        importJson(await _file!.readAsString(), notify: false);
      } catch (e) {
        debugPrint('Forma: nie udało się wczytać danych: $e');
        // zachowujemy uszkodzony plik zamiast go nadpisać
        await _file!.copy('${dir.path}/forma.broken.json');
      }
    }
  }

  String exportJson() => jsonEncode({
        'format': 'forma',
        'v': 1,
        'profile': profile.toJson(),
        'sessions': sessions.map((s) => s.toJson()).toList(),
        'checkins': checkins.map((c) => c.toJson()).toList(),
        'hrv': hrv.map((h) => h.toJson()).toList(),
        'stats': stats.map((k, v) => MapEntry(k, v.toJson())),
      });

  void importJson(String raw, {bool notify = true}) {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    if (j['format'] != 'forma') throw const FormatException('To nie są dane Formy.');
    profile = Profile.fromJson((j['profile'] as Map).cast<String, dynamic>());
    sessions
      ..clear()
      ..addAll(((j['sessions'] as List?) ?? const [])
          .map((e) => Session.fromJson((e as Map).cast<String, dynamic>())));
    sessions.sort((a, b) => a.start.compareTo(b.start));
    checkins
      ..clear()
      ..addAll(((j['checkins'] as List?) ?? const [])
          .map((e) => CheckIn.fromJson((e as Map).cast<String, dynamic>())));
    hrv
      ..clear()
      ..addAll(((j['hrv'] as List?) ?? const []).map((e) => HrvMeasure.fromJson((e as Map).cast<String, dynamic>())));
    stats
      ..clear()
      ..addAll(((j['stats'] as Map?) ?? const {})
          .map((k, v) => MapEntry(k as String, ExStat.fromJson((v as Map).cast<String, dynamic>()))));
    if (notify) notifyListeners();
  }

  Future<void> save() async {
    notifyListeners();
    final f = _file;
    if (f == null) return;
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(exportJson(), flush: true);
    await tmp.rename(f.path);
  }

  void touch() => notifyListeners();

  ExStat stat(String id) => stats.putIfAbsent(id, () => ExStat());

  CheckIn? get todayCheckIn {
    final now = DateTime.now();
    for (final c in checkins.reversed) {
      if (c.at.year == now.year && c.at.month == now.month && c.at.day == now.day) return c;
    }
    return null;
  }

  HrvMeasure? get todayHrv {
    final now = DateTime.now();
    for (final h in hrv.reversed) {
      if (now.difference(h.at).inHours < 20) return h;
    }
    return null;
  }

  Future<void> addCheckIn(CheckIn c) async {
    checkins.removeWhere((x) => _sameDay(x.at, c.at));
    checkins.add(c);
    if (checkins.length > 400) checkins.removeRange(0, checkins.length - 400);
    await save();
  }

  Future<void> addHrv(HrvMeasure m) async {
    hrv.add(m);
    if (hrv.length > 400) hrv.removeRange(0, hrv.length - 400);
    await save();
  }

  Future<void> addSession(Session s) async {
    sessions.add(s);
    for (final d in s.done) {
      final st = stat(d.exId);
      st.count++;
      st.last = s.end;
    }
    await save();
  }

  Future<void> deleteSession(Session s) async {
    sessions.remove(s);
    await save();
  }

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
}
