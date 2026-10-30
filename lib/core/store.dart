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
