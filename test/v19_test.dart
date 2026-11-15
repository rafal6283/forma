import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:forma/core/badges.dart';
import 'package:forma/core/body_checks.dart';
import 'package:forma/core/command.dart';
import 'package:forma/core/day_factors.dart';
import 'package:forma/core/library.dart';
import 'package:forma/core/models.dart';
import 'package:forma/core/progress.dart';
import 'package:forma/core/rep_counter.dart';
import 'package:forma/core/trainer.dart';
import 'package:forma/core/weather.dart';

void main() {
  final lib = Library.parse(File('assets/exercises.json').readAsStringSync());
  final now = DateTime(2026, 11, 13, 7); // piątek rano

  Session sess(DateTime d, List<DoneItem> done, {WorkoutKind kind = WorkoutKind.upper}) => Session(
        id: '${d.millisecondsSinceEpoch}',
        start: d,
        end: d.add(const Duration(minutes: 30)),
        kind: kind,
        title: 'T',
        done: done,
        kcal: 200,
        rpe: 7,
      );

  test('polecenie zwykłym zdaniem', () {
    final c = parseCommand('20 minut na brzuch, bez skakania, lekko', {'chair'});
    expect(c.minutes, 20);
    expect(c.kind, WorkoutKind.core);
    expect(c.quiet, isTrue);
    expect(c.load, 0.85);
    final d = parseCommand('Mocno nogi z hantlami pół godziny', {'chair'});
    expect(d.minutes, 30);
    expect(d.kind, WorkoutKind.lower);
    expect(d.equipment, containsAll(['db', 'chair']));
    expect(d.load, 1.1);
    expect(parseCommand('tabata cicho kwadrans', {}).format, WorkoutFormat.tabata);
    expect(parseCommand('xyz', {}).isEmpty, isTrue);
  });

  test('czynniki dnia z innych aplikacji wpływają na gotowość', () {
    Uint8List file(String src, List<Map<String, Object?>> days) =>
        Uint8List.fromList(utf8.encode(jsonEncode({'format': 'czynniki-dnia', 'source': src, 'days': days})));
    final (s1, d1) = DayFactors.parse(file('rytm-snu', [
      {'date': '2026-11-13', 'sleep_min': 290, 'score': 45, 'awakenings': 5},
    ]))!;
    final (s2, d2) = DayFactors.parse(file('dziennik-talerza', [
      {'date': '2026-11-12', 'kcal': 2600, 'alcohol': 2, 'last_meal_h': 22.5, 'big_meal_kcal': 900},
    ]))!;
    final f = DayFactors({s1: d1, s2: d2});
    expect(DayFactors.parse(Uint8List.fromList(utf8.encode('{"format":"inny"}'))), isNull);
    final base = Trainer(profile: Profile(), sessions: const [], library: lib.all, now: now).readiness();
    final r = Trainer(profile: Profile(), sessions: const [], library: lib.all, now: now, factors: f).readiness();
    expect(r.score, lessThan(base.score - 10));
    final labels = r.factors.map((x) => x.label).toList();
    expect(labels, containsAll(['Jakość snu', 'Alkohol wczoraj', 'Późna kolacja']));
    final back = DayFactors.fromJson(jsonDecode(jsonEncode(f.toJson())) as Map<String, Object?>);
    expect(back.sleep(now)?['score'], 45);
  });

  test('bilans partii, blok z tygodniem lżejszym, szacowany max', () {
    final s = [
      for (var i = 0; i < 8; i++)
        sess(now.subtract(Duration(days: 2 + i * 3)), [
          for (var k = 0; k < 3; k++) DoneItem('pushups', 40, 0, reps: 12, target: 12),
          DoneItem('db_curl', 40, 0, reps: 10, target: 10, weight: 10 + i.toDouble()),
        ]),
    ];
    final t = Trainer(profile: Profile(equipment: {'db', 'chair'}), sessions: s, library: lib.all, now: now);
    final b = t.balance();
    expect(b.push, greaterThan(b.pull));
    expect(b.pullLow, isTrue);
    expect(b.note, contains('ciągnięcia'));
    final orm = t.oneRepMax('db_curl');
    expect(orm.length, 8);
    expect(orm.map((x) => x.$2).reduce((a, c) => a > c ? a : c), closeTo(17 * (1 + 10 / 30), 0.01));
    // blok: 5. tydzień od pierwszego treningu przy regularnych treningach = lżejszy
    final first = DateTime(2026, 10, 14);
    final t5 = Trainer(
        profile: Profile(blockStart: first),
        sessions: [for (var i = 0; i < 8; i++) sess(now.subtract(Duration(days: i * 3)), const [])],
        library: lib.all,
        now: now);
    expect(t5.blockWeek(), 5);
    final p = t5.generate(kind: WorkoutKind.fullBody, readiness: const Readiness(80, [], true), seed: 1);
    expect(p.reasons.any((x) => x.startsWith('Tydzień lżejszy')), isTrue);
  });

  test('przerwa na ruch i trening w parku', () {
    final t = Trainer(profile: Profile(), sessions: const [], library: lib.all, now: now);
    final b = t.moveBreak();
    expect(b.items.length, inInclusiveRange(4, 9));
    expect(b.seconds, lessThan(400));
    final o = t.outdoor();
    expect(o.items.any((i) => i.exId == 'step_ups'), isTrue);
  });

  test('ruchomość i postawa z punktów', () {
    expect(MobilityResult.squatScore(60), 100);
    expect(MobilityResult.overheadScore(120), 0);
    final r = MobilityResult(now, squatKnee: 120, overhead: 170, fold: 70);
    expect(r.focus, contains('deep_squat_hold'));
    expect(r.focus, isNot(contains('wall_angels')));
    expect(extreme([for (var i = 0; i < 100; i++) i.toDouble()], min: true), 5);

    // przodem: prawy bark (po lewej na zdjęciu) niżej o ~5°
    final front = PostureResult.front({
      'shoulderL': const P3(300, 400),
      'shoulderR': const P3(100, 417.5),
      'hipL': const P3(260, 700),
      'hipR': const P3(140, 700),
      'nose': const P3(200, 250),
    });
    expect(front.shoulderTilt!, closeTo(5, 0.2));
    expect(front.hipTilt!, closeTo(0, 0.01));
    expect(front.findings.first.$3, isFalse);
    // bokiem: ucho przed barkiem (w stronę nosa)
    final side = PostureResult.side({
      'earL': const P3(230, 200),
      'shoulderL': const P3(200, 320),
      'hipL': const P3(200, 600),
      'nose': const P3(260, 210),
    });
    expect(side.forwardHead!, closeTo(14, 0.5));
    expect(side.roundedShoulders!, closeTo(0, 0.01));
  });

  test('różnica stron w liczeniu kamerą', () {
    final m = RepModel(Track.knee, 180, 90);
    final c = RepCounter(m);
    var ms = 0.0;
    for (var r = 0; r < 6; r++) {
      final side = r.isEven ? 'L' : 'R';
      final depth = side == 'L' ? 1.0 : 0.75;
      for (var i = 0; i <= 20; i++) {
        final p = (i <= 10 ? i / 10 : (20 - i) / 10) * depth;
        c.add(180 - 90 * p, ms, side: side);
        ms += 60;
      }
    }
    expect(c.reps, 6);
    final (l, rr) = c.asymmetry!;
    expect(l, greaterThan(rr + 15));
  });

  test('pogoda z odpowiedzi Open-Meteo', () {
    final w = Weather.parse('Warszawa', {
      'current': {'temperature_2m': 14.2, 'weather_code': 1, 'wind_speed_10m': 9.0},
      'daily': {
        'temperature_2m_max': [16.0],
        'precipitation_probability_max': [10],
      },
    })!;
    expect(w.outdoorOk, isTrue);
    expect(w.label, 'małe zachmurzenie');
    final rain = Weather.parse('X', {
      'current': {'temperature_2m': 9, 'weather_code': 63, 'wind_speed_10m': 5},
      'daily': {'precipitation_probability_max': [90]},
    })!;
    expect(rain.outdoorOk, isFalse);
  });

  test('odznaki i wyzwanie sezonu', () {
    final s = [
      for (var i = 0; i < 12; i++)
        sess(DateTime(2026, 10, 20 + i, i == 0 ? 6 : 18), [DoneItem('pushups', 40, 0, reps: 20, target: 20)]),
    ];
    final st = Streaks.of(s, const [], 3, now: DateTime(2026, 11, 1, 12));
    final b = badgesFor(
      sessions: s,
      external: const [],
      st: st,
      tests: const [],
      mobility: const [],
      postures: const [],
      hrv: const [],
      now: DateTime(2026, 11, 1, 12),
    );
    bool has(String id) => b.firstWhere((x) => x.id == id).earned;
    expect(has('first'), isTrue);
    expect(has('s10'), isTrue);
    expect(has('streak7'), isTrue);
    expect(has('early'), isTrue);
    expect(has('push100'), isTrue);
    expect(has('s50'), isFalse);
    final (name, days, need, _) = seasonChallenge(st, DateTime(2026, 11, 1));
    expect(name, 'Jesień 2026');
    expect(days, 12);
    expect(need, 30);
    expect(seasonOf(DateTime(2026, 12, 5)).$1, 'Zima 2027');
  });
}
