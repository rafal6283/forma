import 'package:flutter_test/flutter_test.dart';
import 'package:forma/core/models.dart';
import 'package:forma/core/watch_hr.dart';

/// Tętno z zegarka (Huawei → Health Sync → Health Connect) dopisywane do treningu po fakcie.
void main() {
  final start = DateTime(2026, 11, 20, 18);
  final end = start.add(const Duration(minutes: 10));

  test('gęste próbki (trening włączony na zegarku): średnia, maksimum, strefy', () {
    final samples = [for (var s = 0; s <= 600; s += 5) (start.add(Duration(seconds: s)), s < 300 ? 120 : 160)];
    final w = WatchHr.fromSamples(samples, start, end, 180)!;
    expect(w.hr, hasLength(120));
    expect(w.coverage, 1.0);
    expect(w.max, 160);
    expect(w.avg, closeTo(140, 1));
    expect(w.zones.reduce((a, b) => a + b), 600);
    expect(w.zones[1], greaterThan(0)); // 120/180 = 67% → strefa 2
    expect(w.zones[3], greaterThan(0)); // 160/180 = 89% → strefa 4
  });

  test('rzadkie próbki: przerwy do 3 min wypełnione, dłuższe puste', () {
    final w = WatchHr.fromSamples([(start, 100), (start.add(const Duration(minutes: 8)), 110)], start, end, 180)!;
    expect(w.hr.first, 100);
    expect(w.hr[60], 0); // 5 min — ponad 3 min od próbki
    expect(w.hr.last, 110);
    expect(w.coverage, lessThan(0.6));
    expect(WatchHr.fromSamples(const [], start, end, 180), isNull);
    expect(WatchHr.fromSamples([(start, 20), (start, 300)], start, end, 180), isNull); // błędne odczyty odrzucone
  });

  test('sesja dostaje tętno z oznaczeniem źródła, reszta bez zmian', () {
    final s = Session(id: 'x', start: start, end: end, kind: WorkoutKind.upper, title: 'Góra', done: const [], kcal: 90, rpe: 7);
    final samples = [for (var t = 0; t <= 600; t += 30) (start.add(Duration(seconds: t)), 130)];
    final out = WatchHr.fromSamples(samples, start, end, 180)!.apply(s);
    expect((out.avgHr, out.maxHr, out.hrSource, out.rpe, out.title), (130, 130, 'watch', 7, 'Góra'));
    expect(Session.fromJson(out.toJson()).hrSource, 'watch');
  });
}
