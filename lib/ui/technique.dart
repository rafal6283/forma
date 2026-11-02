import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/figure.dart';
import '../core/models.dart';
import 'theme.dart';

/// Części ciała postaci i mięśnie, które w nich „świecą” podczas ruchu.
const partMuscles = {
  'thigh': ['quads', 'hamstrings', 'adductors', 'abductors'],
  'shin': ['calves'],
  'pelvis': ['glutes', 'abductors'],
  'abs': ['abs', 'obliques', 'lower_back'],
  'chest': ['chest', 'upper_back', 'lats', 'traps'],
  'shoulder': ['shoulders', 'traps'],
  'upperArm': ['biceps', 'triceps'],
  'forearm': ['forearms'],
};

/// Siła podświetlenia części (1 = mięsień główny, 0,5 = pomocniczy).
Map<String, double> glowFor(Exercise e) {
  final out = <String, double>{};
  partMuscles.forEach((part, ms) {
    var v = 0.0;
    for (final m in ms) {
      v = math.max(v, e.muscles[m] ?? 0);
    }
    if (v > 0) out[part] = v;
  });
  return out;
}

/// Kolor podświetlenia pracującego mięśnia.
Color glowColor(double strength) => Color.lerp(C.accent, const Color(0xFFFFD166), 0.25)!.withValues(alpha: strength);

/// Staw, który porusza się najbardziej w bieżącym odcinku — przy nim rysujemy strzałkę ruchu.
const _arrowJoints = ['hip', 'neck', 'haN', 'knN', 'anN', 'head', 'haF', 'anF'];

(String, Offset, Offset)? moveArrow(Joints now, Joints target) {
  String? best;
  var d = 0.0;
  for (final k in _arrowJoints) {
    final v = (target[k] - now[k]).distance;
    if (v > d) {
      d = v;
      best = k;
    }
  }
  if (best == null || d < 0.06) return null;
  return (best, now[best], target[best]);
}

/// Łukowata strzałka od [a] w stronę [b] (współrzędne ekranu), przezroczystość [alpha].
void paintArrow(Canvas c, Offset a, Offset b, double alpha, double unit) {
  final v = b - a;
  if (v.distance < 2 || alpha <= 0.02) return;
  final len = math.min(v.distance, unit * 0.45).clamp(18.0, 90.0);
  final dir = v / v.distance;
  final n = Offset(-dir.dy, dir.dx);
  // odsunięcie od ciała, żeby strzałka nie zasłaniała stawu
  final start = a + n * (unit * 0.16);
  final end = start + dir * len;
  final mid = (start + end) / 2 + n * (len * 0.18);
  final paint = Paint()
    ..color = C.accent.withValues(alpha: 0.9 * alpha)
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(2.5, unit * 0.022)
    ..strokeCap = StrokeCap.round;
  c.drawPath(Path()
    ..moveTo(start.dx, start.dy)
    ..quadraticBezierTo(mid.dx, mid.dy, end.dx, end.dy), paint);
  // grot w kierunku stycznej na końcu
  final tan = end - mid;
  final td = tan.distance == 0 ? dir : tan / tan.distance;
  final tn = Offset(-td.dy, td.dx);
  final h = math.max(8.0, unit * 0.06);
  c.drawPath(
    Path()
      ..moveTo(end.dx + td.dx * h * 0.5, end.dy + td.dy * h * 0.5)
      ..lineTo(end.dx - td.dx * h * 0.6 + tn.dx * h * 0.55, end.dy - td.dy * h * 0.6 + tn.dy * h * 0.55)
      ..lineTo(end.dx - td.dx * h * 0.6 - tn.dx * h * 0.55, end.dy - td.dy * h * 0.6 - tn.dy * h * 0.55)
      ..close(),
    Paint()..color = C.accent.withValues(alpha: 0.95 * alpha),
  );
}
