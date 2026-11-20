import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:forma/core/library.dart';
import 'package:forma/core/scene.dart';

/// Fizyka animacji: zgodność z wzorcem (tool/physics.py → test/fixtures/physics_ref.json),
/// brak przenikania przez krzesło/ścianę i podłogę.
void main() {
  final lib = Library.parse(File('assets/exercises.json').readAsStringSync());
  Scene scene(String id) => Scene(lib.all.firstWhere((e) => e.id == id).anim);

  test('Dart liczy to samo co tool/physics.py', () {
    final ref = jsonDecode(File('test/fixtures/physics_ref.json').readAsStringSync()) as Map<String, dynamic>;
    final bad = <String>[];
    ref.forEach((id, frames) {
      final sc = scene(id);
      for (final f in frames as List) {
        final t = (f[0] as num).toDouble();
        final (_, j) = sc.frameAt(t);
        (f[1] as Map<String, dynamic>).forEach((k, v) {
          final p = j.p[k];
          if (p == null) return;
          final d = ((p.dx - (v[0] as num)).abs() + (p.dy - (v[1] as num)).abs());
          if (d > 0.005 && !bad.any((b) => b.startsWith('$id '))) {
            bad.add('$id t=$t $k: ${p.dx.toStringAsFixed(3)},${p.dy.toStringAsFixed(3)} ≠ $v');
          }
        });
      }
    });
    expect(bad.length, 0, reason: bad.join('\n'));
  });

  test('nic nie wchodzi w krzesło, ścianę ani podłogę', () {
    final bad = <String>[];
    for (final e in lib.all) {
      final sc = Scene(e.anim);
      for (var i = 0; i < 24; i++) {
        final (_, j) = sc.frameAt(e.anim.cycle * i / 24);
        final d = sc.penetration(j);
        if (d > 0.025) bad.add('${e.id} $i/24: ${(d * 100).toStringAsFixed(0)} cm w rekwizycie');
        if (!e.anim.hands) {
          for (final v in j.p.values) {
            if (v.dy > 1e-6) bad.add('${e.id} $i/24: pod podłogą');
          }
        }
      }
    }
    expect(bad, isEmpty, reason: bad.take(15).join('\n'));
  });

  test('podpory: dłonie na krześle stoją, stopy w burpee przeskakują za dłońmi', () {
    final inc = scene('incline_pushups');
    final h0 = inc.frameAt(0).$2['haN'], h1 = inc.frameAt(inc.anim.cycle / 2).$2['haN'];
    expect((h0 - h1).distance, lessThan(0.01));
    final b = scene('burpees');
    expect(b.seg.toSet().length, greaterThan(1));
    expect(scene('hip_thrust').pivot, 'neck');
    expect(scene('wall_sit').props.single.type, 'wall');
  });
}
