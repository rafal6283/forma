import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';
import 'progress.dart';

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

/// Dane aplikacji: kilka osób, każda w osobnym pliku JSON; w pamięci dane bieżącej osoby.
class Store extends ChangeNotifier {
  Store._();
  static final instance = Store._();

  // --- bieżąca osoba
  Profile profile = Profile();
  final List<Session> sessions = [];
  final List<CheckIn> checkins = [];
  final List<HrvMeasure> hrv = [];
  final List<Measurement> measurements = [];
  final Map<String, ExStat> stats = {};
  Program? program; // plan wielotygodniowy (aktywny lub zakończony)
  final List<FitTest> tests = [];
  final List<CustomWorkout> customs = [];
  final List<ExternalActivity> external = [];
  final Map<String, ChallengeProgress> challenges = {};
  HealthSnapshot health = HealthSnapshot.empty;

  // --- osoby
  final List<UserRef> users = [];
  String userId = 'u1';

  late Directory _dir;
  File _userFile(String id) => File('${_dir.path}/forma_$id.json');
  File get _index => File('${_dir.path}/forma_users.json');

  UserRef get currentUser => users.firstWhere((u) => u.id == userId, orElse: () => UserRef(userId, profile.name));

  Future<void> load() async {
    _dir = await getApplicationDocumentsDirectory();
    if (await _index.exists()) {
      try {
        final j = jsonDecode(await _index.readAsString()) as Map<String, dynamic>;
        users
          ..clear()
          ..addAll(((j['users'] as List?) ?? const []).map((e) => UserRef.fromJson((e as Map).cast<String, dynamic>())));
        userId = j['current'] as String? ?? (users.isNotEmpty ? users.first.id : 'u1');
      } catch (e) {
        debugPrint('Forma: indeks osób: $e');
      }
    }
    if (users.isEmpty) {
      // pierwsza wersja trzymała dane jednej osoby w forma.json
      final old = File('${_dir.path}/forma.json');
      if (await old.exists()) await old.rename(_userFile('u1').path);
      users.add(UserRef('u1', ''));
      userId = 'u1';
    }
    await _loadUser(userId);
    if (currentUser.name.isEmpty && profile.name.isNotEmpty) currentUser.name = profile.name;
    await _saveIndex();
  }

  Future<void> _loadUser(String id) async {
    _clear();
    final f = _userFile(id);
    if (await f.exists()) {
      try {
        _applyUser(await f.readAsString());
      } catch (e) {
        debugPrint('Forma: nie udało się wczytać danych: $e');
        await f.copy('${_dir.path}/forma_$id.broken.json');
      }
    }
  }

  void _clear() {
    profile = Profile();
    sessions.clear();
    checkins.clear();
    hrv.clear();
    measurements.clear();
    stats.clear();
    program = null;
    tests.clear();
    customs.clear();
    external.clear();
    challenges.clear();
    health = HealthSnapshot.empty;
  }

  Future<void> _saveIndex() async {
    final tmp = File('${_index.path}.tmp');
    await tmp.writeAsString(jsonEncode({'current': userId, 'users': users.map((u) => u.toJson()).toList()}), flush: true);
    await tmp.rename(_index.path);
  }

  String exportUserJson() => jsonEncode({
        'format': 'forma',
        'v': 2,
        'profile': profile.toJson(),
        'sessions': sessions.map((s) => s.toJson()).toList(),
        'checkins': checkins.map((c) => c.toJson()).toList(),
        'hrv': hrv.map((h) => h.toJson()).toList(),
        'measurements': measurements.map((m) => m.toJson()).toList(),
        'stats': stats.map((k, v) => MapEntry(k, v.toJson())),
        if (program != null) 'program': program!.toJson(),
        'tests': tests.map((t) => t.toJson()).toList(),
        'challenges': challenges.map((k, v) => MapEntry(k, v.toJson())),
        'customs': customs.map((c) => c.toJson()).toList(),
        'external': external.map((e) => e.toJson()).toList(),
      });

  void _applyUser(String raw) {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    if (j['format'] != 'forma') throw const FormatException('To nie są dane Formy.');
    List<T> list<T>(String k, T Function(Map<String, dynamic>) f) =>
        ((j[k] as List?) ?? const []).map((e) => f((e as Map).cast<String, dynamic>())).toList();
    profile = Profile.fromJson((j['profile'] as Map).cast<String, dynamic>());
    sessions
      ..clear()
      ..addAll(list('sessions', Session.fromJson))
      ..sort((a, b) => a.start.compareTo(b.start));
    checkins
      ..clear()
      ..addAll(list('checkins', CheckIn.fromJson));
    hrv
      ..clear()
      ..addAll(list('hrv', HrvMeasure.fromJson));
    measurements
      ..clear()
      ..addAll(list('measurements', Measurement.fromJson))
      ..sort((a, b) => a.at.compareTo(b.at));
    stats
      ..clear()
      ..addAll(((j['stats'] as Map?) ?? const {})
          .map((k, v) => MapEntry(k as String, ExStat.fromJson((v as Map).cast<String, dynamic>()))));
    program = j['program'] == null ? null : Program.fromJson((j['program'] as Map).cast<String, dynamic>());
    tests
      ..clear()
      ..addAll(list('tests', FitTest.fromJson));
    challenges
      ..clear()
      ..addAll(((j['challenges'] as Map?) ?? const {})
          .map((k, v) => MapEntry(k as String, ChallengeProgress.fromJson((v as Map).cast<String, dynamic>()))));
    customs
      ..clear()
      ..addAll(list('customs', CustomWorkout.fromJson));
    external
      ..clear()
      ..addAll(list('external', ExternalActivity.fromJson))
      ..sort((a, b) => a.start.compareTo(b.start));
  }

  /// Dopisuje aktywności z zewnątrz (bez duplikatów); zwraca liczbę nowych.
  Future<int> addExternal(Iterable<ExternalActivity> list) async {
    final have = {for (final e in external) e.id};
    var n = 0;
    for (final a in list) {
      if (have.add(a.id)) {
        external.add(a);
        n++;
      }
    }
    if (n > 0) {
      external.sort((a, b) => a.start.compareTo(b.start));
      await save();
    }
    return n;
  }

  // ------------------------------------------------------------ kopia całej rodziny

  /// Wszystkie osoby — do kopii na Koofr.
  Future<String> exportAll() async {
    await save();
    final out = <Map<String, dynamic>>[];
    for (final u in users) {
      final f = _userFile(u.id);
      out.add({'id': u.id, 'name': u.name, 'data': await f.exists() ? await f.readAsString() : null});
    }
    return jsonEncode({'format': 'forma-osoby', 'v': 1, 'current': userId, 'users': out});
  }

  /// Przywraca kopię (wszystkie osoby albo starą kopię jednej osoby).
  Future<void> importAll(String raw) async {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    if (j['format'] == 'forma') {
      _applyUser(raw);
      await save();
      return;
    }
    if (j['format'] != 'forma-osoby') throw const FormatException('To nie jest kopia Formy.');
    users.clear();
    for (final e in (j['users'] as List)) {
      final m = (e as Map).cast<String, dynamic>();
      final u = UserRef(m['id'] as String, m['name'] as String? ?? '');
      users.add(u);
      final data = m['data'] as String?;
      if (data != null) await _userFile(u.id).writeAsString(data, flush: true);
    }
    userId = j['current'] as String? ?? users.first.id;
    if (!users.any((u) => u.id == userId)) userId = users.first.id;
    await _saveIndex();
    await _loadUser(userId);
    notifyListeners();
  }

  // ------------------------------------------------------------ osoby

  Future<void> switchUser(String id) async {
    if (id == userId) return;
    await save();
    userId = id;
    await _saveIndex();
    await _loadUser(id);
    notifyListeners();
  }

  /// Nowa osoba — od razu bieżąca, z pustym profilem (przejdzie wprowadzenie).
  Future<void> addUser(String name) async {
    await save();
    var n = users.length + 1;
    while (users.any((u) => u.id == 'u$n')) {
      n++;
    }
    final u = UserRef('u$n', name);
    users.add(u);
    userId = u.id;
    _clear();
    profile.name = name;
    await save();
    await _saveIndex();
    notifyListeners();
  }

  Future<void> renameUser(String id, String name) async {
    users.firstWhere((u) => u.id == id).name = name;
    if (id == userId) profile.name = name;
    await save();
    await _saveIndex();
  }

  Future<void> deleteUser(String id) async {
    if (users.length < 2) return;
    users.removeWhere((u) => u.id == id);
    final f = _userFile(id);
    if (await f.exists()) await f.delete();
    if (id == userId) {
      userId = users.first.id;
      await _loadUser(userId);
    }
    await _saveIndex();
    notifyListeners();
  }

  // ------------------------------------------------------------ zapis

  Future<void> save() async {
    notifyListeners();
    final f = _userFile(userId);
    final u = users.where((u) => u.id == userId);
    if (u.isNotEmpty && profile.name.isNotEmpty && u.first.name != profile.name) {
      u.first.name = profile.name;
      await _saveIndex();
    }
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(exportUserJson(), flush: true);
    await tmp.rename(f.path);
  }

  void touch() => notifyListeners();

  /// Regularność (dni i tygodnie z rzędu, miesiąc) z treningów i aktywności z zewnątrz.
  Streaks get streaks => Streaks.of(sessions, external, profile.daysPerWeek);

  /// Poziom za regularność.
  Level get level => Level.of(xpFrom(sessions, external, profile.daysPerWeek, tests: tests));

  ExStat stat(String id) => stats.putIfAbsent(id, () => ExStat());

  CheckIn? get todayCheckIn {
    final now = DateTime.now();
    for (final c in checkins.reversed) {
      if (_sameDay(c.at, now)) return c;
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

  /// Ostatnia znana waga: z pomiarów, z Health Connect albo z profilu.
  double get weight {
    for (final m in measurements.reversed) {
      final w = m.values['weight'];
      if (w != null) return w;
    }
    return health.weightKg ?? profile.weightKg;
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

  Future<void> addMeasurement(Measurement m) async {
    measurements.removeWhere((x) => _sameDay(x.at, m.at));
    measurements
      ..add(m)
      ..sort((a, b) => a.at.compareTo(b.at));
    final w = m.values['weight'];
    if (w != null && measurements.last == m) profile.weightKg = w;
    await save();
  }

  Future<void> deleteMeasurement(Measurement m) async {
    measurements.remove(m);
    await save();
  }

  Future<void> addSession(Session s) async {
    sessions.add(s);
    final pr = program;
    if (pr != null && s.programDay != null) {
      for (final d in pr.days) {
        if (d.id == s.programDay) d.sessionId = s.id;
      }
      if (pr.next == null) pr.active = false;
    }
    final ch = s.challenge;
    if (ch != null && ch.contains(':')) {
      final id = ch.split(':').first;
      final day = int.tryParse(ch.split(':').last);
      final cp = challenges[id];
      if (cp != null && day != null) cp.done[day] = s.id;
    }
    for (final d in s.done) {
      final st = stat(d.exId);
      st.count++;
      st.last = s.end;
    }
    await save();
    onSessionAdded?.call();
  }

  /// Wywoływane po zapisaniu treningu (np. przeplanowanie przypomnień).
  static void Function()? onSessionAdded;

  Future<void> deleteSession(Session s) async {
    sessions.remove(s);
    for (final d in program?.days ?? const <ProgramDay>[]) {
      if (d.sessionId == s.id) d.sessionId = null;
    }
    await save();
  }

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
}

extension ProgramStore on Store {
  Future<void> setProgram(Program? p) async {
    program = p;
    await save();
  }
}

extension TestsStore on Store {
  Future<void> addTest(FitTest t) async {
    tests.add(t);
    await save();
  }
}
