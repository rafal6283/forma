import 'dart:math' as math;

import 'figure.dart';
import 'models.dart';

/// Punkt ciała z kamery (współrzędne obrazu; z — głębia szacowana przez model).
class P3 {
  final double x, y, z;
  final double conf;
  const P3(this.x, this.y, [this.z = 0, this.conf = 1]);
}

/// Kąt w stawie b (stopnie, 0–180) między odcinkami b→a i b→c.
double angle3(P3 a, P3 b, P3 c) {
  final ux = a.x - b.x, uy = a.y - b.y, uz = a.z - b.z;
  final vx = c.x - b.x, vy = c.y - b.y, vz = c.z - b.z;
  final nu = math.sqrt(ux * ux + uy * uy + uz * uz), nv = math.sqrt(vx * vx + vy * vy + vz * vz);
  if (nu == 0 || nv == 0) return 180;
  final cos = ((ux * vx + uy * vy + uz * vz) / (nu * nv)).clamp(-1.0, 1.0);
  return math.acos(cos) * 180 / math.pi;
}

/// Śledzony staw: [a, b, c] — kąt w b. Nazwy jak w postaci animacji (bez strony).
enum Track { knee, hip, elbow, shoulder }

const trackLabel = {Track.knee: 'kolano', Track.hip: 'biodro', Track.elbow: 'łokieć', Track.shoulder: 'bark'};

/// Punkty postaci tworzące kąt (środkowy = staw).
const _figJoints = {
  Track.knee: ('hp', 'kn', 'an'),
  Track.hip: ('sh', 'hp', 'kn'),
  Track.elbow: ('sh', 'el', 'ha'),
  Track.shoulder: ('hp', 'sh', 'el'),
};

/// Kąt stawu w pozie animacji (strona N lub F).
double figAngle(Joints j, Track t, String side) {
  final (a, b, c) = _figJoints[t]!;
  P3 p(String k) {
    final o = j['$k$side'];
    return P3(o.dx, o.dy);
  }

  return angle3(p(a), p(b), p(c));
}

/// Wzorzec ruchu z animacji: który staw, kąt startowy, kąt skrajny.
class RepModel {
  final Track track;
  final double start, far;
  const RepModel(this.track, this.start, this.far);

  double get range => (far - start).abs();

  /// Postęp 0 (start) … 1 (pełny zakres) dla kąta.
  double progress(double a) => (a - start) / (far - start);

  /// Z animacji ćwiczenia: staw z największym zakresem ruchu. Null — ćwiczenie statyczne (liczymy czas).
  static RepModel? of(Exercise e) {
    final keys = e.anim.keys;
    if (keys.length < 2 || e.isStatic) return null;
    RepModel? best;
    for (final t in Track.values) {
      for (final side in const ['N', 'F']) {
        final angs = [for (final k in keys) figAngle(Joints.of(k), t, side)];
        final st = angs.first;
        var far = st;
        for (final a in angs) {
          if ((a - st).abs() > (far - st).abs()) far = a;
        }
        final m = RepModel(t, st, far);
        // przy zbliżonym zakresie wolimy staw dolny (stabilniej widoczny)
        if (best == null || m.range > best.range + 5) best = m;
      }
    }
    if (best == null || best.range < 25) return null;
    return best;
  }
}

/// Licznik powtórzeń z kąta stawu: start → zakres → powrót = 1 powtórzenie; ocena zakresu ruchu.
class RepCounter {
  final RepModel model;
  RepCounter(this.model);

  int reps = 0;
  final List<double> roms = []; // zakres każdego powtórzenia (1 = pełny jak w animacji)
  double? _smooth;
  bool _down = false;
  double _peak = 0;
  double _lastRepAt = -1e9;
  double current = 0; // bieżący postęp 0..1+

  static const enter = 0.55, leave = 0.3;

  /// Nowy pomiar kąta w chwili [ms]. Zwraca true, gdy właśnie zaliczono powtórzenie.
  bool add(double angle, double ms) {
    _smooth = _smooth == null ? angle : _smooth! * 0.5 + angle * 0.5;
    final p = model.progress(_smooth!);
    current = p;
    if (!_down) {
      if (p >= enter) {
        _down = true;
        _peak = p;
      }
      return false;
    }
    _peak = math.max(_peak, p);
    if (p <= leave && ms - _lastRepAt > 400) {
      _down = false;
      reps++;
      roms.add(_peak.clamp(0.0, 1.3).toDouble());
      _lastRepAt = ms;
      return true;
    }
    return false;
  }

  double? get lastRom => roms.isEmpty ? null : roms.last;
  double? get avgRom => roms.isEmpty ? null : roms.reduce((a, b) => a + b) / roms.length;

  /// Ocena zakresu w punktach 0–100.
  int? get score => avgRom == null ? null : (math.min(1.0, avgRom!) * 100).round();

  /// Krótka podpowiedź po powtórzeniu.
  String? get cue {
    final r = lastRom;
    if (r == null) return null;
    if (r >= 0.9) return 'Pełny zakres';
    final deeper = model.far < model.start; // zginanie stawu
    return switch (model.track) {
      Track.knee || Track.hip => deeper ? 'Zejdź niżej' : 'Wyprostuj mocniej',
      Track.elbow => deeper ? 'Zegnij łokcie bardziej' : 'Wyprostuj ręce do końca',
      Track.shoulder => 'Większy zakres w barkach',
    };
  }
}

/// Kąt stawu z punktów kamery — strona, która jest dalej w ruchu (działa też dla ćwiczeń jednostronnych).
/// [pts] — klucze: shoulderL/R, elbowL/R, wristL/R, hipL/R, kneeL/R, ankleL/R.
double? cameraAngle(Map<String, P3> pts, RepModel m) {
  double? side(String s) {
    P3? g(String k) => pts['$k$s'];
    final (a, b, c) = switch (m.track) {
      Track.knee => (g('hip'), g('knee'), g('ankle')),
      Track.hip => (g('shoulder'), g('hip'), g('knee')),
      Track.elbow => (g('shoulder'), g('elbow'), g('wrist')),
      Track.shoulder => (g('hip'), g('shoulder'), g('elbow')),
    };
    if (a == null || b == null || c == null) return null;
    if (math.min(a.conf, math.min(b.conf, c.conf)) < 0.5) return null;
    return angle3(a, b, c);
  }

  final l = side('L'), r = side('R');
  if (l == null) return r;
  if (r == null) return l;
  return m.progress(l) >= m.progress(r) ? l : r;
}
