import 'dart:math' as math;

import 'models.dart';

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime _monday(DateTime d) => _day(d).subtract(Duration(days: d.weekday - 1));

/// Regularność: dni z treningiem, serie dni i tygodni, pierścień miesiąca.
/// Liczą się treningi w Formie i aktywności z zewnątrz (bieg, rower…) od 15 min.
class Streaks {
  final Map<DateTime, int> minutesByDay; // dzień → minuty ruchu
  final Set<DateTime> formaDays; // dni z treningiem w Formie
  final int weekTarget;
  final DateTime now;

  Streaks._(this.minutesByDay, this.formaDays, this.weekTarget, this.now);

  factory Streaks.of(List<Session> sessions, List<ExternalActivity> external, int weekTarget, {DateTime? now}) {
    final m = <DateTime, int>{};
    final f = <DateTime>{};
    for (final s in sessions) {
      final d = _day(s.start);
      m[d] = (m[d] ?? 0) + math.max(1, s.duration.inMinutes);
      f.add(d);
    }
    for (final x in external) {
      if (x.minutes < 15) continue;
      final d = _day(x.start);
      m[d] = (m[d] ?? 0) + x.minutes;
    }
    return Streaks._(m, f, math.max(1, weekTarget), now ?? DateTime.now());
  }

  bool active(DateTime d) => minutesByDay.containsKey(_day(d));
  bool get trainedToday => active(now);

  /// Dni z rzędu z ruchem (dzisiejszy liczy się, jeśli już był; inaczej seria trwa od wczoraj).
  int get dayStreak {
    var d = _day(now);
    if (!active(d)) d = d.subtract(const Duration(days: 1));
    var n = 0;
    while (active(d)) {
      n++;
      d = d.subtract(const Duration(days: 1));
    }
    return n;
  }

  int sessionsInWeek(DateTime monday) {
    var n = 0;
    for (var i = 0; i < 7; i++) {
      if (active(monday.add(Duration(days: i)))) n++;
    }
    return n;
  }

  /// Tygodnie z rzędu z zaliczonym celem (bieżący liczy się, gdy już zaliczony).
  int get weekStreak {
    var m = _monday(now);
    if (sessionsInWeek(m) < weekTarget) m = m.subtract(const Duration(days: 7));
    var n = 0;
    while (sessionsInWeek(m) >= weekTarget && n < 520) {
      n++;
      m = m.subtract(const Duration(days: 7));
    }
    return n;
  }

  int get thisWeek => sessionsInWeek(_monday(now));

  /// Ile treningów brakuje do celu tygodnia i ile dni zostało (z dzisiejszym).
  (int, int) get weekLeft {
    final need = math.max(0, weekTarget - thisWeek);
    final daysLeft = 8 - now.weekday - (trainedToday ? 1 : 0);
    return (need, daysLeft);
  }

  /// Seria zagrożona: dziś jeszcze nic, a cel tygodnia wymaga treningu dziś (albo seria dni ≥ 3).
  bool get atRisk {
    if (trainedToday) return false;
    final (need, days) = weekLeft;
    return (need > 0 && need >= days) || dayStreak >= 3;
  }

  String? get riskText {
    if (!atRisk) return null;
    final (need, days) = weekLeft;
    if (need > 0 && need >= days) {
      return need == 1 ? 'Jeden trening dziś i cel tygodnia zaliczony.' : 'Do celu tygodnia brakuje $need treningów — zostało $days dni.';
    }
    return 'Masz $dayStreak dni z rzędu — nie przerywaj serii.';
  }

  /// Pierścień miesiąca: dni z ruchem / cel (tygodniowy cel × liczba tygodni w miesiącu).
  (int, int) month(DateTime m) {
    final first = DateTime(m.year, m.month);
    final days = DateTime(m.year, m.month + 1, 0).day;
    var n = 0;
    for (var i = 0; i < days; i++) {
      if (active(first.add(Duration(days: i)))) n++;
    }
    return (n, (weekTarget * days / 7).round());
  }

  /// Najdłuższa seria dni w historii.
  int get bestDayStreak {
    final ds = minutesByDay.keys.toList()..sort();
    var best = 0, cur = 0;
    DateTime? prev;
    for (final d in ds) {
      cur = prev != null && d.difference(prev).inHours.round() <= 25 && d.day != prev.day ? cur + 1 : 1;
      best = math.max(best, cur);
      prev = d;
    }
    return best;
  }
}

/// Poziom i punkty doświadczenia za regularność.
class Level {
  final int xp, level, floor, next;
  const Level(this.xp, this.level, this.floor, this.next);

  /// Punkty potrzebne na poziom n (łącznie): 60·n·(n−1).
  static int need(int n) => 60 * n * (n - 1);

  factory Level.of(int xp) {
    var l = 1;
    while (need(l + 1) <= xp) {
      l++;
    }
    return Level(xp, l, need(l), need(l + 1));
  }

  double get progress => (xp - floor) / math.max(1, next - floor);

  String get title => switch (level) {
        < 3 => 'Początkujący',
        < 6 => 'Regularny',
        < 10 => 'Wytrwały',
        < 15 => 'Zahartowany',
        < 21 => 'Atleta',
        < 30 => 'Mistrz',
        _ => 'Legenda',
      };
}

/// Skąd się biorą punkty (do pokazania użytkownikowi).
const xpRules = [
  ('Trening w Formie', '20 pkt + 1 pkt za minutę'),
  ('Bieg, rower, spacer z zegarka', '1 pkt za 2 minuty'),
  ('Kolejny dzień z rzędu', '+5 pkt za każdy dzień serii (do 50)'),
  ('Zaliczony cel tygodnia', '+100 pkt'),
  ('Test formy', '+50 pkt'),
];

/// Punkty doświadczenia z całej historii (liczone od nowa, więc zawsze spójne).
int xpFrom(List<Session> sessions, List<ExternalActivity> external, int weekTarget, {List<FitTest> tests = const []}) {
  var xp = 0;
  for (final s in sessions) {
    xp += 20 + math.min(120, s.duration.inMinutes);
  }
  for (final x in external) {
    xp += math.min(90, x.minutes ~/ 2);
  }
  xp += tests.length * 50;
  final st = Streaks.of(sessions, external, weekTarget);
  final days = st.minutesByDay.keys.toList()..sort();
  var run = 0;
  DateTime? prev;
  final weeks = <DateTime, int>{};
  for (final d in days) {
    run = prev != null && _day(prev.add(const Duration(days: 1))) == d ? run + 1 : 1;
    if (run > 1) xp += math.min(50, 5 * (run - 1));
    prev = d;
    final m = _monday(d);
    weeks[m] = (weeks[m] ?? 0) + 1;
  }
  xp += weeks.values.where((n) => n >= math.max(1, weekTarget)).length * 100;
  return xp;
}
