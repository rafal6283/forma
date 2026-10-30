import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:forma/core/figure.dart';
import 'package:forma/core/library.dart';
import 'package:forma/core/models.dart';
import 'package:forma/core/trainer.dart';

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
