import 'dart:math' as math;

import 'body_checks.dart';
import 'models.dart';
import 'progress.dart';

/// Odznaka: (zdobyta?, postęp 0–1, opis postępu).
class Achievement {
  final String id, icon, name, desc;
  final bool earned;
  final double progress;
  final String status;
  const Achievement(this.id, this.icon, this.name, this.desc, this.earned, this.progress, this.status);
}

/// Sezon (pora roku): nazwa, początek, koniec (włącznie).
(String, DateTime, DateTime) seasonOf(DateTime d) {
  final y = d.year;
  if (d.month == 12) return ('Zima ${y + 1}', DateTime(y, 12, 1), DateTime(y + 1, 2, DateTime(y + 1, 3, 0).day));
  if (d.month <= 2) return ('Zima $y', DateTime(y - 1, 12, 1), DateTime(y, 2, DateTime(y, 3, 0).day));
  if (d.month <= 5) return ('Wiosna $y', DateTime(y, 3, 1), DateTime(y, 5, 31));
  if (d.month <= 8) return ('Lato $y', DateTime(y, 6, 1), DateTime(y, 8, 31));
  return ('Jesień $y', DateTime(y, 9, 1), DateTime(y, 11, 30));
}

/// Wyzwanie sezonu: 30 dni z ruchem w bieżącej porze roku.
(String, int, int, int) seasonChallenge(Streaks st, DateTime now) {
  final (name, from, to) = seasonOf(now);
  var days = 0;
  for (var d = from; !d.isAfter(to); d = d.add(const Duration(days: 1))) {
    if (st.active(d)) days++;
  }
  final left = to.difference(DateTime(now.year, now.month, now.day)).inDays + 1;
  return (name, days, 30, left);
}

/// Wszystkie odznaki z historii.
List<Achievement> badgesFor({
  required List<Session> sessions,
  required List<ExternalActivity> external,
  required Streaks st,
  required List<FitTest> tests,
  required List<MobilityResult> mobility,
  required List<PostureResult> postures,
  required List<HrvMeasure> hrv,
  required DateTime now,
}) {
  Achievement count(String id, String icon, String name, int need, int have, String unit) => Achievement(
      id, icon, name, '$need $unit', have >= need, math.min(1, have / need), '${math.min(have, need)}/$need');

  final n = sessions.length;
  final minutes = sessions.fold(0, (a, s) => a + s.duration.inMinutes) + external.fold(0, (a, x) => a + x.minutes);

  // najlepsza seria tygodni z celem
  var bestWeeks = 0, run = 0;
  if (st.minutesByDay.isNotEmpty) {
    final first = st.minutesByDay.keys.reduce((a, b) => a.isBefore(b) ? a : b);
    var m = DateTime(first.year, first.month, first.day).subtract(Duration(days: first.weekday - 1));
    while (!m.isAfter(now)) {
      run = st.sessionsInWeek(m) >= st.weekTarget ? run + 1 : 0;
      bestWeeks = math.max(bestWeeks, run);
      m = m.add(const Duration(days: 7));
    }
  }

  // najwięcej pompek w jednym tygodniu kalendarzowym
  final pushByWeek = <DateTime, int>{};
  for (final s in sessions) {
    final d = DateTime(s.start.year, s.start.month, s.start.day);
    final m = d.subtract(Duration(days: d.weekday - 1));
    for (final x in s.done) {
      if (x.exId.contains('pushup') && x.reps != null) pushByWeek[m] = (pushByWeek[m] ?? 0) + x.reps!;
    }
  }
  final bestPush = pushByWeek.values.fold<int>(0, (a, b) => math.max(a, b));
  final kinds = sessions.map((s) => s.kind).toSet().length;
  final early = sessions.any((s) => s.start.hour < 7);
  final late = sessions.any((s) => s.start.hour >= 21);
  final park = sessions.any((s) => s.title.contains('parku'));
  final (season, sDays, sNeed, _) = seasonChallenge(st, now);

  return [
    count('first', '🌱', 'Pierwszy krok', 1, n, 'trening'),
    count('s10', '💪', 'Rozgrzany', 10, n, 'treningów'),
    count('s50', '🏅', 'Regularny', 50, n, 'treningów'),
    count('s100', '🏆', 'Setka', 100, n, 'treningów'),
    count('s250', '👑', 'Weteran', 250, n, 'treningów'),
    count('streak7', '🔥', 'Tydzień bez przerwy', 7, st.bestDayStreak, 'dni z rzędu'),
    count('streak30', '☄️', 'Miesiąc bez przerwy', 30, st.bestDayStreak, 'dni z rzędu'),
    count('weeks4', '📅', 'Miesiąc celów', 4, bestWeeks, 'tygodnie z celem z rzędu'),
    count('weeks12', '🗓', 'Kwartał celów', 12, bestWeeks, 'tygodni z celem z rzędu'),
    count('min1000', '⏱', '1000 minut', 1000, minutes, 'minut ruchu'),
    count('push100', '🫸', '100 pompek w tygodniu', 100, bestPush, 'pompek'),
    count('kinds', '🎯', 'Wszechstronny', 6, kinds, 'rodzajów treningu'),
    count('hrv7', '💓', 'Słucham serca', 7, hrv.length, 'pomiarów HRV'),
    count('test', '📈', 'Na start', 1, tests.length, 'test formy'),
    count('mobility', '🧘', 'Giętki', 1, mobility.length, 'test ruchomości'),
    count('posture', '🧍', 'Prosto', 1, postures.length, 'ocena postawy'),
    Achievement('early', '🌅', 'Ranny ptaszek', 'trening przed 7:00', early, early ? 1 : 0, early ? 'zdobyta' : '—'),
    Achievement('late', '🌙', 'Nocny marek', 'trening po 21:00', late, late ? 1 : 0, late ? 'zdobyta' : '—'),
    Achievement('park', '🌳', 'W plenerze', 'trening w parku', park, park ? 1 : 0, park ? 'zdobyta' : '—'),
    Achievement('season', '🍂', season, '30 dni ruchu w tej porze roku', sDays >= sNeed, math.min(1, sDays / sNeed),
        '$sDays/$sNeed dni'),
  ];
}
