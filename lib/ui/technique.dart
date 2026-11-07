import 'dart:math' as math;

import 'package:flutter/material.dart';

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
