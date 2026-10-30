import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:forma/core/catalog.dart';
import 'package:forma/core/figure.dart';
import 'package:forma/core/library.dart';
import 'package:forma/core/models.dart';
import 'package:forma/core/tcx.dart';
import 'package:forma/core/trainer.dart';
import 'package:forma/core/voice_commands.dart';

void main() {
  final lib = Library.parse(File('assets/exercises.json').readAsStringSync());

  Trainer make(Profile p, {List<Session> sessions = const [], HealthSnapshot health = HealthSnapshot.empty}) =>
      Trainer(profile: p, sessions: sessions, library: lib.all, health: health, now: DateTime(2026, 10, 30, 8));

  test('baza ćwiczeń: wszystkie pozy i odwołania istnieją', () {
    expect(lib.all.length, greaterThan(50));
    for (final e in lib.all) {
      expect(e.anim.keys, isNotEmpty, reason: e.id);
      if (e.easier != null) expect(lib[e.easier!], isNotNull, reason: e.id);
      if (e.harder != null) expect(lib[e.harder!], isNotNull, reason: e.id);
    }
  });

  test('każde ćwiczenie ma mięśnie, a każda partia ma ćwiczenia', () {
    for (final e in lib.all) {
      expect(e.muscles, isNotEmpty, reason: e.id);
      for (final m in e.muscles.keys) {
        expect(muscleLabel.containsKey(m), isTrue, reason: '${e.id}: $m');
      }
    }
    for (final g in muscleGroups) {
      final n = lib.all.where((e) => e.groups.contains(g)).length;
      expect(n, greaterThanOrEqualTo(8), reason: g);
    }
  });

  test('nazwy z Fitify są przypisane', () {
    final names = {for (final e in lib.all) ...e.aka};
    expect(names.length, greaterThan(250));
    expect(names, containsAll(['Push-Ups', 'Superman', 'Reverse Snow Angels', 'Tricep Dips', 'The Hundred']));
  });

  test('TCX i opis dla Stravy', () {
    final s = Session(
      id: '42',
      start: DateTime(2026, 10, 30, 18),
      end: DateTime(2026, 10, 30, 18, 20),
      kind: WorkoutKind.back,
      title: 'Plecy i barki',
      done: [DoneItem('door_row', 40, 0), DoneItem('door_row', 40, 0), DoneItem('superman', 30, 0)],
      kcal: 150,
      avgHr: 120,
      maxHr: 150,
      hr: [100, 110, 0, 130],
    );
    final x = sessionTcx(s);
    expect(x, contains('<HeartRateBpm><Value>130</Value></HeartRateBpm>'));
    expect(x, contains('<Calories>150</Calories>'));
    expect(sessionDescription(s), contains('Wiosłowanie przy framudze: 2 × 40 s'));
  });

  test('postać nie wchodzi w podłogę', () {
    for (final e in lib.all.where((e) => !e.anim.hands)) {
      for (var i = 0; i < 20; i++) {
        final j = Joints.grounded(e.anim.at(e.anim.cycle * i / 20));
        for (final v in j.p.values) {
          expect(v.dy, lessThanOrEqualTo(1e-6), reason: '${e.id} klatka $i');
        }
      }
    }
  });

  for (final kind in WorkoutKind.values) {
    for (final minutes in [15, 30, 45]) {
      test('plan $kind $minutes min mieści się w czasie', () {
        final t = make(Profile(minutes: minutes, level: 3));
        final plan = t.generate(kind: kind, readiness: const Readiness(70, [], false), seed: 7);
        expect(plan.items, isNotEmpty);
        final diff = (plan.seconds - minutes * 60).abs();
        expect(diff, lessThan(minutes * 60 * 0.35), reason: 'plan ${plan.seconds} s');
        // strony ćwiczeń jednostronnych zawsze w parach
        for (var i = 0; i < plan.items.length; i++) {
          final it = plan.items[i];
          if (it.side == 1) expect(plan.items[i + 1].side, 2);
        }
      });
    }
  }

  test('tabata: bloki po 8 interwałów 20/10', () {
    final t = make(Profile(minutes: 30, level: 3));
    final plan = t.generate(kind: WorkoutKind.hiit, format: WorkoutFormat.tabata, readiness: const Readiness(75, [], true), seed: 2);
    final main = plan.items.where((i) => i.phase == Phase.main).toList();
    expect(main.length % 8, 0);
    expect(main.every((i) => i.work == 20), isTrue);
    expect(plan.format, WorkoutFormat.tabata);
  });

  test('serie i superserie mają cele powtórzeń', () {
    final t = make(Profile(minutes: 40, level: 3, goal: Goal.strength));
    for (final f in [WorkoutFormat.sets, WorkoutFormat.supersets]) {
      final plan = t.generate(kind: WorkoutKind.upper, format: f, readiness: const Readiness(75, [], true), seed: 5);
      final main = plan.items.where((i) => i.phase == Phase.main).toList();
      expect(main, isNotEmpty, reason: '$f');
      expect(main.where((i) => i.reps != null).length, greaterThan(main.length ~/ 2), reason: '$f');
      expect(main.every((i) => i.rounds >= 2), isTrue, reason: '$f');
    }
  });

  test('progresja: wszystkie serie zrobione → cel +1, nie zrobione → bez wzrostu', () {
    final e = lib['pushups']!;
    Session s(List<int> reps) => Session(
          id: 'x',
          start: DateTime(2026, 10, 28, 18),
          end: DateTime(2026, 10, 28, 18, 30),
          kind: WorkoutKind.upper,
          title: 'x',
          done: [for (final r in reps) DoneItem('pushups', 30, 0, reps: r, target: 10)],
          kcal: 100,
          format: WorkoutFormat.sets,
        );
    expect(make(Profile(level: 3), sessions: [s([10, 10, 10])]).repsTarget(e, 3), 11);
    expect(make(Profile(level: 3), sessions: [s([10, 9, 7])]).repsTarget(e, 3), lessThanOrEqualTo(10));
  });

  test('plan wielotygodniowy: dni, tydzień lżejszy, kolejka', () {
    final t = make(Profile(goal: Goal.strength, daysPerWeek: 3));
    final p = t.buildProgram(weeks: 8, weekdays: [1, 3, 5], minutes: 30, start: DateTime(2026, 11, 2));
    expect(p.days.length, 24);
    expect(p.days.where((d) => d.week == 4).every((d) => d.deload), isTrue);
    expect(p.days.where((d) => d.week == 2).every((d) => !d.deload), isTrue);
    expect(p.next!.id, 'w1d1');
    p.days.first.sessionId = 's1';
    expect(p.next!.id, 'w1d2');
    expect(p.days.map((d) => d.format).toSet(), contains(WorkoutFormat.sets));
  });

  test('serie tygodnia liczone na partię', () {
    final s = Session(
      id: 'w',
      start: DateTime(2026, 10, 27, 18),
      end: DateTime(2026, 10, 27, 18, 30),
      kind: WorkoutKind.upper,
      title: 'x',
      done: [DoneItem('pushups', 30, 0, reps: 10), DoneItem('pushups', 30, 0, reps: 10), DoneItem('squat', 30, 0)],
      kcal: 100,
    );
    final w = make(Profile(), sessions: [s]).weeklySets();
    expect(w['klatka'], 2);
    expect(w['nogi'], 1);
  });

  test('komendy głosowe', () {
    expect(VoiceCommands.parse('dalej')!.$1, VoiceCmd.next);
    expect(VoiceCommands.parse('to jest za trudne')!.$1, VoiceCmd.harder);
    expect(VoiceCommands.parse('pauza')!.$1, VoiceCmd.pause);
    expect(VoiceCommands.parse('boli mnie kolano')!.$1, VoiceCmd.pain);
    expect(VoiceCommands.parse('12'), (VoiceCmd.setReps, 12));
    expect(VoiceCommands.parse('ile zostało')!.$1, VoiceCmd.remaining);
    expect(VoiceCommands.parse('dzień dobry'), isNull);
  });

  test('gotowe programy i wyzwania mają poprawne ćwiczenia', () {
    for (final t in programTemplates) {
      for (final id in t.prefer) {
        expect(lib[id], isNotNull, reason: '${t.id}: $id');
      }
      final p = make(Profile()).buildProgram(weeks: t.weeks, weekdays: List.generate(t.week.length, (i) => i + 1),
          minutes: t.minutes, week: t.week, name: t.name, templateId: t.id, prefer: t.prefer);
      expect(p.days.length, t.weeks * t.week.length, reason: t.id);
    }
    for (final c in challengeDefs) {
      expect(lib[c.exId], isNotNull, reason: c.id);
      expect(c.target(c.days), greaterThan(c.target(1)), reason: c.id);
      final total = c.target(10);
      expect(c.split(total).fold(0, (a, b) => a + b), total, reason: c.id);
      expect(c.split(total).every((x) => x <= c.perSet), isTrue, reason: c.id);
    }
  });

  test('wynik testu formy', () {
    final t = FitTest(DateTime(2026, 10, 31), pushups: 20, squats: 44, plank: 90);
    expect(t.parts['Pompki'], 50);
    expect(t.parts['Przysiady'], 80);
    expect(t.parts['Deska'], 50);
    expect(t.score, 60);
  });

  test('ograniczenia i brak sprzętu są respektowane', () {
    final p = Profile(limits: {'kolana', 'nadgarstki'}, equipment: {}, noJumping: true, level: 3);
    final t = make(p);
    for (final kind in WorkoutKind.values) {
      final plan = t.generate(kind: kind, readiness: const Readiness(80, [], true), seed: 3);
      for (final it in plan.items) {
        final e = lib[it.exId]!;
        expect(e.stress.contains('kolana'), isFalse, reason: e.id);
        expect(e.stress.contains('nadgarstki'), isFalse, reason: e.id);
        expect(e.impact, isFalse, reason: e.id);
        expect(e.needsEquipment, isFalse, reason: e.id);
      }
    }
  });

  test('słaby sen obniża gotowość, a niska gotowość daje mobilność', () {
    final t = make(Profile(), health: const HealthSnapshot(sleepHours: 4));
    final r = t.readiness();
    expect(r.score, lessThan(70));
    final low = make(Profile()).recommendKind(const Readiness(30, [], true));
    expect(low.$1, WorkoutKind.mobility);
  });

  test('poziom rośnie po lekkim treningu i spada po za ciężkim', () {
    final p = Profile(level: 3);
    final t = make(p);
    Session s(int rpe) => Session(
          id: '1',
          start: DateTime(2026, 10, 29, 18),
          end: DateTime(2026, 10, 29, 18, 30),
          kind: WorkoutKind.fullBody,
          title: 'x',
          done: [DoneItem('squat', 600, 0)],
          kcal: 200,
          rpe: rpe,
          plannedSeconds: 600,
        );
    expect(t.nextLevel(s(4)), greaterThan(3));
    expect(t.nextLevel(s(10)), lessThan(3));
  });

  test('RMSSD z odstępów RR', () {
    final rr = [for (var i = 0; i < 60; i++) i.isEven ? 1000.0 : 1040.0];
    expect(Trainer.rmssd(rr), closeTo(40, 0.01));
    expect(Trainer.rmssd([1000, 1000]), isNull);
  });
}
