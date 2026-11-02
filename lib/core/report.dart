import 'dart:math' as math;

import 'models.dart';
import 'trainer.dart';

/// Rekord pobity w raportowanym tygodniu.
class WeekRecord {
  final String exId, name;
  final int value, before;
  final bool reps;
  WeekRecord(this.exId, this.name, this.value, this.before, this.reps);
  String get label => reps ? '$value powt. (było $before)' : '$value s (było $before s)';
}

/// Tygodniowy raport trenera: co poszło dobrze, co poprawić, prognoza i porównanie miesięczne.
class WeekReport {
  final DateTime monday;
  final bool current; // tydzień w trakcie
  final int sessions, target, minutes, kcal, sets, reps;
  final int prevSessions, prevMinutes;
  final double avgRpe, completion;
  final Map<String, int> groupSets;
  final int setTarget;
  final List<WeekRecord> records;
  final List<String> good, improve, forecast;
  // miesiąc: ostatnie 4 tygodnie vs 4 wcześniejsze
  final int month, prevMonth, monthMin, prevMonthMin;
  final FitTest? fitNow, fitBefore;
  final bool testDue;

  WeekReport._({
    required this.monday,
    required this.current,
    required this.sessions,
    required this.target,
    required this.minutes,
    required this.kcal,
    required this.sets,
    required this.reps,
    required this.prevSessions,
    required this.prevMinutes,
    required this.avgRpe,
    required this.completion,
    required this.groupSets,
    required this.setTarget,
    required this.records,
    required this.good,
    required this.improve,
    required this.forecast,
    required this.month,
    required this.prevMonth,
    required this.monthMin,
    required this.prevMonthMin,
    required this.fitNow,
    required this.fitBefore,
    required this.testDue,
  });

  DateTime get sunday => monday.add(const Duration(days: 6));

  /// Który tydzień pokazać domyślnie: w poniedziałek i wtorek — zakończony, potem — bieżący.
  static int defaultWeeksAgo(DateTime now) => now.weekday <= 2 ? 1 : 0;

  static WeekReport of(Trainer t, {List<FitTest> tests = const [], Program? program, int weeksAgo = 0}) {
    final now = t.now;
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: now.weekday - 1 + 7 * weeksAgo));
    final next = monday.add(const Duration(days: 7));
    final prevMonday = monday.subtract(const Duration(days: 7));
    final byId = {for (final e in t.library) e.id: e};
    bool inRange(Session s, DateTime a, DateTime b) => !s.start.isBefore(a) && s.start.isBefore(b);

    final week = t.sessions.where((s) => inRange(s, monday, next)).toList();
    final prev = t.sessions.where((s) => inRange(s, prevMonday, monday)).toList();
    int mins(List<Session> l) => l.fold(0, (a, s) => a + s.duration.inMinutes);

    var sets = 0, reps = 0;
    for (final s in week) {
      for (final d in s.done) {
        final e = byId[d.exId];
        if (e == null || d.side == 2) continue;
        if (e.type == ExType.warmup || e.type == ExType.stretch) continue;
        sets++;
        reps += d.reps ?? 0;
      }
    }

    // rekordy: najlepszy wynik w tygodniu vs najlepszy wcześniej
    final before = <String, (int, bool)>{};
    final inWeek = <String, (int, bool)>{};
    for (final s in t.sessions.where((s) => s.start.isBefore(next))) {
      final bucket = inRange(s, monday, next) ? inWeek : before;
      for (final d in s.done) {
        final e = byId[d.exId];
        if (e == null || e.type == ExType.warmup || e.type == ExType.stretch) continue;
        final isReps = d.reps != null;
        final v = d.reps ?? (e.isStatic ? d.seconds : -1);
        if (v <= 0) continue;
        final cur = bucket[d.exId];
        if (cur == null || v > cur.$1) bucket[d.exId] = (v, isReps);
      }
    }
    final records = <WeekRecord>[
      for (final e in inWeek.entries)
        if (before[e.key] != null && before[e.key]!.$2 == e.value.$2 && e.value.$1 > before[e.key]!.$1)
          WeekRecord(e.key, byId[e.key]?.name ?? e.key, e.value.$1, before[e.key]!.$1, e.value.$2),
    ]..sort((a, b) => (b.value / b.before).compareTo(a.value / a.before));

    final groupSets = t.weeklySets(at: monday);
    final setTarget = t.weeklySetTarget;
    final rpe = week.isEmpty ? 0.0 : week.fold(0, (a, s) => a + s.rpe) / week.length;
    final completion = week.isEmpty ? 0.0 : week.fold(0.0, (a, s) => a + s.completion) / week.length;
    final hiZone = week.fold(0, (a, s) => a + s.zones[3] + s.zones[4]);
    final allZone = week.fold(0, (a, s) => a + s.zones.fold(0, (x, y) => x + y));
    final hard = <String>{
      for (final s in week)
        for (final f in s.feedback.entries)
          if (f.value > 0) byId[f.key]?.name ?? f.key,
    };
    final target = t.profile.daysPerWeek;
    final kcal = week.fold(0.0, (a, s) => a + s.kcal).round();
    final daysLeft = weeksAgo == 0 ? 7 - now.weekday : 0;

    // --- co poszło dobrze
    final good = <String>[
      if (week.length >= target) 'Cel tygodnia zaliczony: ${week.length} z $target treningów.',
      if (week.length < target && week.isNotEmpty && daysLeft > 0)
        'Już ${week.length} z $target treningów — zostało $daysLeft dni.',
      if (mins(week) > mins(prev) && prev.isNotEmpty) 'Więcej ruchu niż tydzień wcześniej: ${mins(week)} min (było ${mins(prev)}).',
      if (records.isNotEmpty)
        'Rekordy: ${records.take(3).map((r) => '${r.name} ${r.value}${r.reps ? '' : ' s'}').join(', ')}.',
      if (completion >= 0.9 && week.isNotEmpty) 'Treningi robione do końca (${(completion * 100).round()}% planu).',
      if (groupSets.values.every((v) => v >= setTarget ~/ 2) && week.isNotEmpty) 'Wszystkie partie dostały pracę.',
      if (week.any((s) => s.hrr != null && s.hrr! >= 25)) 'Tętno dobrze spada po wysiłku — kondycja rośnie.',
    ];

    // --- co poprawić
    final weakGroups = [for (final e in groupSets.entries) if (e.value < setTarget ~/ 2) e.key];
    final improve = <String>[
      if (week.length < target && daysLeft == 0) 'Zabrakło ${target - week.length} treningów do celu — w kolejnym tygodniu zaplanuj stałe dni.',
      if (week.length < target && daysLeft > 0 && week.length + daysLeft < target)
        'Do celu brakuje ${target - week.length} treningów, a zostało $daysLeft dni.',
      if (weakGroups.isNotEmpty && week.isNotEmpty)
        'Mało serii: ${weakGroups.take(3).join(', ')} (cel ok. $setTarget w tygodniu).',
      if (allZone > 0 && hiZone / allZone > 0.35) 'Dużo czasu w strefach 4–5 tętna — dorzuć spokojniejszy trening.',
      if (rpe >= 8.5) 'Treningi oceniasz jako bardzo ciężkie — warto dać sobie lżejszy dzień.',
      if (completion > 0 && completion < 0.7) 'Część treningów kończyła się przed czasem — skrócę je albo zmniejszę tempo.',
      if (hard.isNotEmpty) 'Za trudne były: ${hard.take(3).join(', ')} — trener dobierze łatwiejsze wersje.',
      if (week.isEmpty) 'W tym tygodniu jeszcze nie było treningu — nawet 15 minut się liczy.',
    ];

    // --- prognoza na kolejny tydzień
    final forecast = <String>[];
    final pr = program;
    if (pr != null && pr.active) {
      final nextMon = next;
      final nextSun = nextMon.add(const Duration(days: 7));
      final days = pr.days.where((d) => !d.date.isBefore(nextMon) && d.date.isBefore(nextSun)).toList();
      if (days.isNotEmpty) {
        final deload = days.first.load < 0.95;
        forecast.add('Plan „${pr.name}”: tydzień ${days.first.week}/${pr.weeks}, ${days.length} treningi'
            '${deload ? ' — tydzień lżejszy (regeneracja)' : ' — objętość ×${days.first.load.toStringAsFixed(2)}'}.');
        forecast.add('Rodzaje: ${days.map((d) => kindLabel[d.kind]!.toLowerCase()).toSet().join(', ')}.');
      } else {
        forecast.add('Plan „${pr.name}” dobiega końca — czas na test formy i nowy plan.');
      }
    } else {
      forecast.add('Proponuję $target treningi${weakGroups.isNotEmpty ? ', z naciskiem na: ${weakGroups.take(2).join(' i ')}' : ''}.');
    }
    if (week.isNotEmpty) {
      if (rpe <= 5.5 && completion >= 0.9) {
        forecast.add('Było lekko — podniosę intensywność (więcej powtórzeń, krótsze przerwy).');
      } else if (rpe >= 8.5 || completion < 0.7) {
        forecast.add('Było ciężko — zostawię objętość albo lekko odpuszczę.');
      } else {
        forecast.add('Obciążenie w normie — dalej stopniowa progresja.');
      }
    }
    if (records.isNotEmpty) forecast.add('Cele powtórzeń rosną po Twoich rekordach.');

    // --- miesiąc i test formy
    final m0 = next.subtract(const Duration(days: 28));
    final m1 = m0.subtract(const Duration(days: 28));
    final monthL = t.sessions.where((s) => inRange(s, m0, next)).toList();
    final prevL = t.sessions.where((s) => inRange(s, m1, m0)).toList();
    final sortedTests = [...tests]..sort((a, b) => a.at.compareTo(b.at));
    final fitNow = sortedTests.isEmpty ? null : sortedTests.last;
    FitTest? fitBefore;
    if (fitNow != null) {
      for (final ft in sortedTests.reversed) {
        if (fitNow.at.difference(ft.at).inDays >= 21) {
          fitBefore = ft;
          break;
        }
      }
    }
    final testDue = fitNow == null || now.difference(fitNow.at).inDays >= 28;
    if (testDue) forecast.add('Zrób test formy — porównam wynik z poprzednim miesiącem.');

    return WeekReport._(
      monday: monday,
      current: weeksAgo == 0,
      sessions: week.length,
      target: target,
      minutes: mins(week),
      kcal: kcal,
      sets: sets,
      reps: reps,
      prevSessions: prev.length,
      prevMinutes: mins(prev),
      avgRpe: rpe,
      completion: completion,
      groupSets: groupSets,
      setTarget: setTarget,
      records: records,
      good: good,
      improve: improve,
      forecast: forecast,
      month: monthL.length,
      prevMonth: prevL.length,
      monthMin: mins(monthL),
      prevMonthMin: mins(prevL),
      fitNow: fitNow,
      fitBefore: fitBefore,
      testDue: testDue,
    );
  }

  /// Zmiana składowych testu formy (punkty 0–100).
  Map<String, int> get fitDelta {
    final a = fitBefore, b = fitNow;
    if (a == null || b == null) return const {};
    final pa = a.parts, pb = b.parts;
    return {for (final k in pb.keys) if (pa.containsKey(k)) k: pb[k]! - pa[k]!};
  }

  int get monthChangePct => prevMonthMin == 0 ? 0 : ((monthMin - prevMonthMin) * 100 / math.max(1, prevMonthMin)).round();
}
