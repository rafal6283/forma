import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:forma/core/figure.dart';
import 'package:forma/core/library.dart';

void main() {
  test('ręce odwiedzone w bok (ab) w widoku z boku: dłonie na wysokości barków, poza płaszczyzną', () {
    final j = Joints.of(const Pose(an: [0, 0], af: [0, 0], ab: [90, 90, 0, 0]));
    expect(j['haN'].dy, closeTo(j['shN'].dy, 1e-6));
    expect(j.z['haN']!, closeTo(0.58, 1e-3));
    expect(j.z['haF']!, closeTo(-0.58, 1e-3));
  });

  test('łopatki (sp/se) przesuwają całą rękę, kolano na bok (kr) zostawia stopę', () {
    const base = Pose(an: [0, 0], af: [0, 0]);
    final a = Joints.of(base);
    final b = Joints.of(const Pose(an: [0, 0], af: [0, 0], sp: 0.04, se: 0.03));
    expect(b['haN'].dx - a['haN'].dx, closeTo(0.04, 1e-6));
    expect(b['haN'].dy - a['haN'].dy, closeTo(-0.03, 1e-6));
    const bent = Pose(t: 90, back: true, ln: [150, 90], lf: [150, 90]);
    final c = Joints.of(bent), d = Joints.of(const Pose(t: 90, back: true, ln: [150, 90], lf: [150, 90], kr: [60, -60]));
    expect(d['anN'], c['anN']);
    expect(d.z['knN']!, greaterThan(0.1));
    expect(d.z['knF']!, greaterThan(0.1)); // obie kolana na tę samą stronę
  });

  test('skręt barków i druga strona', () {
    const p = Pose(an: [90, 90], af: [90, 90], rot: 45);
    final j = Joints.of(p);
    expect(j.rot, 45);
    expect(j.z['haN']!, lessThan(-0.05)); // ręce w przód skręcone w stronę dalszego barku
    final s = p.swapped();
    expect(s.rot, -45);
    expect(Pose(ab: const [1, 2, 3, 4], kr: const [5, 6]).swapped().ab, [2, 1, 4, 3]);
  });

  test('ruch ciągły (flow) przechodzi przez klatki bez zatrzymań', () {
    final lib = Library.parse(File('assets/exercises.json').readAsStringSync());
    final hip = lib.all.firstWhere((e) => e.id == 'hip_circles').anim;
    expect(hip.flow, isTrue);
    expect(hip.cam, isNotNull);
    final per = hip.cycle / hip.keys.length;
    // w klatce kluczowej poza = klatka; tuż obok ruch trwa (brak przytrzymania)
    expect(hip.at(per).x, closeTo(hip.keys[1].x, 1e-9));
    expect((hip.at(per * 1.1).x - hip.at(per).x).abs(), greaterThan(1e-3));
    final circles = lib.all.firstWhere((e) => e.id == 'arm_circles').anim;
    expect(circles.keys.length, 8);
    for (final id in ['scap_pushup', 'fire_hydrant', 'reverse_angels', 'lumbar_rotation']) {
      final a = lib.all.firstWhere((e) => e.id == id).anim;
      expect(a.keys.any((k) => k.outOfPlane), isTrue, reason: id);
    }
  });
}
