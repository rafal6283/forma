import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:forma/core/activity_import.dart';
import 'package:forma/core/figure.dart';
import 'package:forma/core/library.dart';
import 'package:forma/core/models.dart';
import 'package:forma/core/ppg.dart';
import 'package:forma/core/progress.dart';
import 'package:forma/core/rep_counter.dart';
import 'package:forma/core/trainer.dart';

void main() {
  final lib = Library.parse(File('assets/exercises.json').readAsStringSync());
  final now = DateTime(2026, 11, 6, 8); // piątek

  Trainer make(Profile p, {List<Session> sessions = const [], List<ExternalActivity> external = const []}) =>
      Trainer(profile: p, sessions: sessions, library: lib.all, external: external, now: now);

  Session sess(DateTime d, {int min = 30, List<DoneItem>? done, int rpe = 7}) => Session(
        id: '${d.millisecondsSinceEpoch}',
        start: d,
        end: d.add(Duration(minutes: min)),
        kind: WorkoutKind.lower,
        title: 'Nogi',
        done: done ?? [DoneItem('squat', 45, 0, reps: 15, target: 15)],
        kcal: 200,
        rpe: rpe,
      );

  group('regularność i poziom', () {
    test('seria dni, tygodnie i zagrożony cel', () {
      final s = [
        sess(DateTime(2026, 11, 3, 18)),
        sess(DateTime(2026, 11, 4, 18)),
        sess(DateTime(2026, 11, 5, 18)),
      ];
      final run = ExternalActivity(
          id: 'strava:1', source: 'strava', name: 'Bieg', sport: 'Run', start: DateTime(2026, 11, 2, 7), minutes: 40);
      final st = Streaks.of(s, [run], 4, now: now);
      expect(st.dayStreak, 4); // pn bieg + wt–czw treningi
      expect(st.thisWeek, 4);
      expect(st.weekStreak, 1);
      expect(st.trainedToday, isFalse);
      expect(st.atRisk, isTrue); // 4 dni z rzędu
      expect(st.formaDays.length, 3);
      final (done, goal) = st.month(now);
      expect(done, 4);
      expect(goal, 17);
    });

    test('poziom rośnie z punktami', () {
      expect(Level.of(0).level, 1);
      expect(Level.of(Level.need(2)).level, 2);
      final l = Level.of(Level.need(5) + 10);
      expect(l.level, 5);
      expect(l.progress, greaterThan(0));
      expect(l.progress, lessThan(1));
      final xp = xpFrom([sess(DateTime(2026, 11, 4, 18)), sess(DateTime(2026, 11, 5, 18))], const [], 2);
      // 2 × (20 + 30) + seria 5 + cel tygodnia 100
      expect(xp, 205);
    });
  });

  group('trener', () {
    test('szybkie 7 minut: 12 pozycji po 30 s, bez skoków gdy wyłączone', () {
      final t = make(Profile(noJumping: true));
      final p = t.quick7();
      final slots = p.items.where((i) => i.side != 2).length;
      expect(slots, 12);
      expect(p.seconds, inInclusiveRange(7 * 60 - 20, 8 * 60));
      for (final it in p.items) {
        expect(lib[it.exId]!.impact, isFalse, reason: it.exId);
      }
    });

    test('drop-sety: po serii lżejsza wersja, ciężar 70%', () {
      final t = make(Profile(goal: Goal.strength, equipment: {'chair', 'db'}));
      final p = t.generate(
          kind: WorkoutKind.upper, format: WorkoutFormat.dropSets, readiness: const Readiness(75, [], true), seed: 3);
      final drops = p.items.where((i) => i.tag?.startsWith('Drop') == true).toList();
      expect(drops, isNotEmpty);
      expect(Trainer.dropWeight(10), 7);
      expect(Trainer.dropWeight(8), 5.5);
    });

    test('podpowiedź ciężaru: wszystkie powtórzenia zrobione → więcej', () {
      final s = sess(DateTime(2026, 11, 4, 18), done: [
        DoneItem('db_curl', 40, 0, reps: 12, target: 12, weight: 8),
        DoneItem('db_curl', 40, 0, reps: 12, target: 12, weight: 8),
      ]);
      final t = make(Profile(equipment: {'db'}), sessions: [s]);
      expect(t.weightFor(lib['db_curl']!), 9);
      final s2 = sess(DateTime(2026, 11, 4, 18), done: [DoneItem('db_curl', 40, 0, reps: 9, target: 12, weight: 8)]);
      expect(make(Profile(equipment: {'db'}), sessions: [s2]).weightFor(lib['db_curl']!), 8);
    });

    test('zmęczenie mięśni: wczorajsze nogi i bieg → trener omija nogi', () {
      final legs = sess(DateTime(2026, 11, 5, 18), done: [
        for (var i = 0; i < 4; i++) DoneItem('squat', 45, 0, reps: 15, target: 15),
        for (var i = 0; i < 4; i++) DoneItem('reverse_lunge', 45, 1, reps: 12, target: 12),
      ]);
      final run = ExternalActivity(
          id: 'strava:2', source: 'strava', name: 'Bieg', sport: 'Run', start: DateTime(2026, 11, 5, 7), minutes: 50, avgHr: 150);
      final t = make(Profile(), sessions: [legs], external: [run]);
      final f = t.muscleFatigue();
      expect(f['quads']!, greaterThan(0.6));
      expect(f['calves']!, greaterThan(0.3));
      expect(f['chest'] ?? 0, lessThan(0.1));
      final p = t.generate(kind: WorkoutKind.fullBody, readiness: const Readiness(70, [], true), seed: 4);
      final main = p.items.where((i) => i.phase == Phase.main).map((i) => lib[i.exId]!).toList();
      final legHeavy = main.where((e) => (e.muscles['quads'] ?? 0) >= 1).length;
      expect(legHeavy, lessThanOrEqualTo(main.length ~/ 3));
      expect(p.reasons.any((r) => r.startsWith('Zmęczone mięśnie')), isTrue);
      // bieg obniża gotowość
      expect(t.readiness().factors.any((x) => x.label == 'Bieg'), isTrue);
    });

    test('własny trening: kolejność, strony i kod do udostępnienia', () {
      final w = CustomWorkout(id: 'c1', name: 'Poranek', rounds: 2, items: [
        CustomItem(exId: 'squat', reps: 15),
        CustomItem(exId: 'side_plank', seconds: 30),
        CustomItem(exId: 'pushups', reps: 10, rest: 30),
      ]);
      final p = make(Profile()).customPlan(w);
      expect(p.items.first.exId, 'squat');
      expect(p.items.where((i) => i.exId == 'side_plank').length, 4); // 2 rundy × 2 strony
      expect(p.items.where((i) => i.side == 2), isNotEmpty);
      final code = customCode(w);
      expect(code, startsWith('FORMA1:'));
      final back = customFromCode('Spróbuj: $code !', id: 'x', known: lib.byId.keys.toSet())!;
      expect(back.name, 'Poranek');
      expect(back.items.map((i) => i.exId), ['squat', 'side_plank', 'pushups']);
      expect(back.items[1].reps, isNull);
      expect(customFromCode('FORMA1:zepsute', id: 'y'), isNull);
    });
  });

  test('aktywność z zegarka pokrywająca trening Formy jest pomijana', () {
    final s = sess(DateTime(2026, 11, 4, 18), min: 40);
    final same = ExternalActivity(
        id: 'strava:9', source: 'strava', name: 'Trening', sport: 'Workout', start: DateTime(2026, 11, 4, 18, 2), minutes: 38);
    final other = ExternalActivity(
        id: 'strava:10', source: 'strava', name: 'Bieg', sport: 'Run', start: DateTime(2026, 11, 4, 7), minutes: 30);
    expect(overlapsForma(same, [s]), isTrue);
    expect(overlapsForma(other, [s]), isFalse);
    final j = ExternalActivity.fromJson(other.toJson());
    expect(j.sportLabel, 'Bieg');
    expect(j.load, greaterThan(0));
  });

  test('HRV z aparatu: syntetyczny puls 62 bpm', () {
    final rnd = math.Random(1);
    final beats = <double>[0];
    while (beats.last < 62000) {
      beats.add(beats.last + 968 + (rnd.nextDouble() - 0.5) * 120);
    }
    final t = <double>[], v = <double>[];
    var x = 0.0, j = 0;
    while (x < 60000) {
      while (beats[j + 1] <= x) {
        j++;
      }
      final ph = (x - beats[j]) / (beats[j + 1] - beats[j]);
      t.add(x);
      v.add(150 - 3 * math.exp(-math.pow((ph - 0.15) / 0.07, 2)) + 2 * math.sin(x / 4000) + (rnd.nextDouble() - 0.5));
      x += 33.3;
    }
    final r = Ppg.analyze(t, v)!;
    expect(r.bpm, inInclusiveRange(59, 65));
    expect(r.quality, greaterThan(0.8));
    expect(r.rmssd, isNotNull);
    expect(r.rmssd!, inInclusiveRange(20, 90));
    // brak sygnału
    expect(Ppg.analyze(t, [for (final _ in t) 100.0]), isNull);
  });

  group('kamera', () {
    test('wzorzec ruchu z animacji: przysiad → kolano, pompka → łokieć', () {
      expect(RepModel.of(lib['squat']!)!.track, anyOf(Track.knee, Track.hip));
      expect(RepModel.of(lib['pushups']!)!.track, Track.elbow);
      expect(RepModel.of(lib['plank']!), isNull);
      final known = lib.all.where((e) => RepModel.of(e) != null).length;
      expect(known, greaterThan(100));
    });

    test('licznik: 5 przysiadów, ostatni płytki', () {
      final m = RepModel.of(lib['squat']!)!;
      final c = RepCounter(m);
      var ms = 0.0;
      for (var r = 0; r < 5; r++) {
        final depth = r == 4 ? 0.65 : 1.0;
        for (var i = 0; i <= 40; i++) {
          final p = math.sin(math.pi * i / 40) * depth;
          c.add(m.start + (m.far - m.start) * p, ms);
          ms += 50;
        }
      }
      expect(c.reps, 5);
      expect(c.roms.last, lessThan(0.8));
      expect(c.cue, isNot('Pełny zakres'));
      expect(c.score!, inInclusiveRange(80, 100));
    });

    test('kąt z punktów kamery', () {
      final pts = {
        'hipL': const P3(0, 0),
        'kneeL': const P3(0, 1),
        'ankleL': const P3(1, 1),
      };
      final m = RepModel(Track.knee, 180, 90);
      expect(cameraAngle(pts, m)!, closeTo(90, 0.01));
      expect(angle3(const P3(0, 0), const P3(0, 1), const P3(0, 2)), closeTo(180, 0.01));
      expect(figAngle(Joints.of(const Pose()), Track.knee, 'N'), greaterThan(150));
    });
  });
}
