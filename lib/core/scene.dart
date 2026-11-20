import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'figure.dart';

/// Rekwizyt w świecie ćwiczenia. Krzesło: [rect] od siedziska (top) do podłogi; ściana: płyta 4 cm.
class SceneProp {
  final String type; // chair / wall / bar
  final Rect rect;
  const SceneProp(this.type, this.rect);
}

/// Kończyna z końcem trzymanym na podporze: (korzeń, staw środkowy, kostka lub null, dł. 1, dł. 2).
typedef _Limb = (String, String, String?, double, double);

const Map<String, _Limb> _ends = {
  'toN': ('hpN', 'knN', 'anN', Body.thigh, Body.shin),
  'toF': ('hpF', 'knF', 'anF', Body.thigh, Body.shin),
  'haN': ('shN', 'elN', null, Body.upper, Body.fore),
  'haF': ('shF', 'elF', null, Body.upper, Body.fore),
};
const _limbAb = {'haN': 0, 'haF': 1, 'toN': 2, 'toF': 3};
const _pivots = ['toN', 'toF', 'anN', 'anF', 'haN', 'haF', 'knN', 'knF', 'hip', 'neck', 'head'];
const _eps = 0.03;

typedef _J = Map<String, Offset>;

_J _shift(_J j, double dx, double dy) => j.map((k, v) => MapEntry(k, Offset(v.dx + dx, v.dy + dy)));

double _relDeg(double a) => (a + 180) % 360 - 180;

double _hyp(Offset a, Offset b) => (a - b).distance;

/// Dwa odcinki od [root] do [target]: zgięcie w stronę naturalną (bez przeprostu); gdy obie strony są
/// możliwe — po tej samej stronie co [mid] w pozie. Zwraca (staw środkowy, koniec).
(Offset, Offset) ik2(Offset root, Offset mid, Offset target, double l1, double l2,
    {bool back = false, bool arm = false}) {
  final dx = target.dx - root.dx, dy = target.dy - root.dy;
  var d = math.sqrt(dx * dx + dy * dy);
  d = math.min(math.max(d, (l1 - l2).abs() + 1e-4), l1 + l2 - 1e-4);
  final base = math.atan2(dx, dy);
  final phi = math.acos(((l1 * l1 + d * d - l2 * l2) / (2 * l1 * d)).clamp(-1.0, 1.0));
  final sgn = (back ? -1.0 : 1.0) * (arm ? -1.0 : 1.0);
  (Offset, Offset, double) sol(double a) {
    final m = Offset(root.dx + math.sin(a) * l1, root.dy + math.cos(a) * l1);
    final tx = target.dx - m.dx, ty = target.dy - m.dy;
    var n = math.sqrt(tx * tx + ty * ty);
    if (n == 0) n = 1;
    final e = Offset(m.dx + tx / n * l2, m.dy + ty / n * l2);
    final flex = _relDeg(a * 180 / math.pi - math.atan2(e.dx - m.dx, e.dy - m.dy) * 180 / math.pi) * sgn;
    return (m, e, flex);
  }

  final s1 = sol(base - phi), s2 = sol(base + phi);
  if (s1.$3 >= -1 && s2.$3 < -1) return (s1.$1, s1.$2);
  if (s2.$3 >= -1 && s1.$3 < -1) return (s2.$1, s2.$2);
  final cross = dx * (mid.dy - root.dy) - dy * (mid.dx - root.dx);
  final s = cross > 0 ? s1 : s2;
  return (s.$1, s.$2);
}

/// Fizyka sceny (wzorzec: tool/physics.py — oba muszą liczyć to samo). Rekwizyty ustawione według pierwszej
/// klatki, ciało opiera się o podłogę albo siedzisko; podpora (stopa, dłoń, kolano…) stoi w miejscu, a w
/// przejściach, w których inna kończyna wyraźnie nie pracuje (wyrzut nóg w burpee), podporą jest ona.
/// Dłonie i stopy opierające się w dwóch kolejnych klatkach trzymane są na podporze (IK kończyny), przy
/// przestawieniu idą łukiem nad podłogą; wolna kończyna omija podłogę; nic nie wchodzi w podłogę ani krzesło.
class Scene {
  final FigAnim anim;
  late final List<Pose> keys = anim.keys;
  final props = <SceneProp>[];
  late final bool hasChair;
  String? pivot;
  Offset? pin;
  var world = <_J>[];
  var seg = <String>[];
  final ends = <String, List<Offset?>>{};

  Scene(this.anim) {
    final raw = anim.props;
    hasChair = raw.any((p) => p['type'] == 'chair');
    final first = Joints.grounded(keys.first, hands: anim.hands).p;
    for (final p in raw) {
      final dx = (p['dx'] as num?)?.toDouble() ?? 0;
      switch (p['type']) {
        case 'chair':
          final pt = (p['at'] as String?) ?? 'haN';
          final w = (p['w'] as num?)?.toDouble() ?? 0.4;
          final x0 = first[pt]!.dx + dx - w / 2;
          // punkt podparcia leży NA siedzisku, a nie w nim
          final top = first[pt]!.dy + Body.thickness(pt);
          props.add(SceneProp('chair', Rect.fromLTRB(x0, top, x0 + w, 0)));
        case 'wall':
          final double x;
          if (p['touch'] == 'back') {
            // ściana tuż za plecami (biodra, kark, głowa) w pierwszej klatce
            final x1 = ['hip', 'neck', 'head'].map((k) => first[k]!.dx - Body.thickness(k)).reduce(math.min) + dx;
            x = x1 - 0.04;
          } else {
            final at = p['at'] as String?;
            x = at != null ? first[at]!.dx + dx : (p['x'] as num?)?.toDouble() ?? -0.1;
          }
          props.add(SceneProp('wall', Rect.fromLTRB(x, -1.9, x + 0.04, 0)));
        case 'bar':
          final h = first['haN']!;
          props.add(SceneProp('bar', Rect.fromLTRB(h.dx - 0.55, h.dy - 0.02, h.dx + 0.55, h.dy + 0.02)));
      }
    }
    if (anim.hands || anim.pin == 'none') return;
    final dropped = [for (final k in keys) _drop(Joints.of(k).p, k)];
    if (anim.pin != null) {
      pivot = anim.pin; // wskazany: opiera się w pierwszej klatce, w kolejnych trzymamy go w miejscu
    } else {
      // podpora: punkt opierający się w każdej klatce, przy którym pozostałe takie punkty najmniej się przesuwają
      final at = [for (final p in raw) if (p['type'] == 'chair' && p['at'] != null) p['at'] as String];
      // klatki w powietrzu (wyskok) nie decydują o podporze
      var ground = [for (var i = 0; i < keys.length; i++) if (keys[i].lift == 0) dropped[i]];
      if (ground.isEmpty) ground = dropped;
      final always = <String>[
        for (final c in <String>{'toN', 'toF', ...at, ..._pivots})
          if (ground.every((j) => _touching(j, c))) c
      ];
      (double, String)? best;
      for (final c in always) {
        var moved = 0.0;
        for (final o in always) {
          final xs = [for (final j in ground) j[o]!.dx - j[c]!.dx];
          moved += xs.reduce(math.max) - xs.reduce(math.min);
        }
        if (best == null || moved < best.$1 - 1e-6) best = (moved, c);
      }
      if (best != null) {
        pivot = best.$2;
        // deska: gdy stopy przestawiają się względem dłoni (wspinacz, wskok do przysiadu) — stoją dłonie
        final hands = [for (final c in ['haN', 'haF']) if (always.contains(c)) c];
        if ((pivot == 'toN' || pivot == 'toF') && hands.isNotEmpty) {
          final xs = [for (final j in ground) j[pivot]!.dx - j[hands.first]!.dx];
          if (xs.reduce(math.max) - xs.reduce(math.min) > 0.3) pivot = hands.first;
        }
      }
    }
    final pv = pivot;
    if (pv == null) return;
    pin = dropped.first[pv];
    world = [for (final j in dropped) _shift(j, pin!.dx - j[pv]!.dx, pin!.dy - j[pv]!.dy)];
    _segmentPivots(dropped);
    if (keys.any((k) => k.front)) return;
    final n = keys.length;
    for (final MapEntry(key: c, value: li) in _limbAb.entries) {
      if (seg.every((p) => p == c) || keys.any((k) => k.ab[li] != 0)) continue;
      if (c.startsWith('to') && keys.any((k) => k.kr[c.endsWith('N') ? 0 : 1] != 0)) continue;
      final List<bool> flags;
      if (anim.fix.contains(c)) {
        flags = List.filled(n, true);
      } else {
        // dłoń przy głowie (splecione za głową w brzuszkach) nie podpiera ciała
        flags = [
          for (var i = 0; i < n; i++)
            keys[i].lift == 0 &&
                _touching(world[i], c, 0.045) &&
                !(c.startsWith('ha') && _hyp(world[i][c]!, world[i]['head']!) < 0.25)
        ];
      }
      if (flags.any((f) => f)) ends[c] = _anchors(c, flags);
    }
  }

  /// O ile stopni zmieniają się stawy kończyny c między pozami (biodro+kolano / bark+łokieć).
  double _limbChange(String c, Pose a, Pose b) {
    List<double> limb(Pose p) => c.startsWith('ha')
        ? (c.endsWith('N') ? p.an : p.af)
        : (c.endsWith('N') ? p.ln : p.lf);
    final pa = limb(a), pb = limb(b);
    return _relDeg((pa[0] - a.t) - (pb[0] - b.t)).abs() + _relDeg((pa[0] - pa[1]) - (pb[0] - pb[1])).abs();
  }

  /// Podpora w każdym przejściu (jak _segment_pivots w physics.py).
  void _segmentPivots(List<_J> dropped) {
    final n = keys.length;
    seg = List.filled(n, pivot!);
    if (n < 2 || anim.pin != null) return;
    final s = List.of(seg);
    for (var i = 0; i < n; i++) {
      final b = (i + 1) % n;
      final ka = keys[i], kb = keys[b];
      if (ka.lift != 0 || kb.lift != 0 || ka.front || kb.front) continue;
      final cand = [for (final c in _ends.keys) if (_touching(dropped[i], c) && _touching(dropped[b], c)) c];
      if (cand.isEmpty) continue;
      final pv = pivot!;
      final double base;
      if (_touching(dropped[i], pv) && _touching(dropped[b], pv)) {
        if (!_ends.containsKey(pv)) continue; // podpora na kolanach/biodrach/plecach zostaje
        base = _limbChange(pv, ka, kb);
      } else {
        base = 1e9;
      }
      var c = cand.first;
      for (final o in cand) {
        if (_limbChange(o, ka, kb) < _limbChange(c, ka, kb)) c = o;
      }
      final rel = ((dropped[b][c]!.dx - dropped[b][pv]!.dx) - (dropped[i][c]!.dx - dropped[i][pv]!.dx)).abs();
      final ch = _limbChange(c, ka, kb);
      if (base > 60 && (ch < 0.5 * base && rel > 0.3 || ch < 15)) s[i] = c;
    }
    if (_listEq(s, seg)) return;
    final w = [world.first];
    for (var i = 0; i < n - 1; i++) {
      final c = s[i];
      w.add(_shift(dropped[i + 1], w[i][c]!.dx - dropped[i + 1][c]!.dx, 0));
    }
    final c = s[n - 1];
    if ((w[n - 1][c]!.dx - w.first[c]!.dx).abs() > 0.02) return;
    seg = s;
    world = w;
  }

  static bool _listEq(List<String> a, List<String> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Punkt oparcia w każdej klatce (null = w powietrzu); bliskie (< 15 cm) w jednym ciągu dzielą punkt.
  List<Offset?> _anchors(String c, List<bool> flags) {
    final n = flags.length;
    final out = List<Offset?>.filled(n, null);
    final starts = flags.every((f) => f)
        ? [0]
        : [for (var i = 0; i < n; i++) if (flags[i] && !flags[(i - 1 + n) % n]) i];
    final fixed = anim.fix.contains(c);
    for (final st in starts) {
      final run = <int>[];
      var i = st;
      while (flags[i] && run.length < n) {
        run.add(i);
        i = (i + 1) % n;
      }
      final base = fixed ? world.first[c]! : world[st][c]!;
      final compact = fixed || run.every((k) => _hyp(world[k][c]!, base) < 0.15);
      for (final k in run) {
        out[k] = compact ? base : world[k][c];
      }
    }
    // w przejściach, w których c jest podporą, stoi dokładnie tam, gdzie przypięliśmy ciało
    for (var k = 0; k < seg.length; k++) {
      if (seg[k] == c && out[k] != null && out[(k + 1) % n] != null) {
        out[k] = out[(k + 1) % n] = world[k][c];
      }
    }
    return out;
  }

  double _supportY(String k, double x) {
    var y = 0.0;
    for (final p in props) {
      if (p.type == 'chair' && p.rect.left - 0.01 <= x && x <= p.rect.right + 0.01) y = math.min(y, p.rect.top);
    }
    return y;
  }

  double _gap(_J j) {
    var g = double.infinity;
    j.forEach((k, v) => g = math.min(g, _supportY(k, v.dx) - (v.dy + Body.thickness(k))));
    return g;
  }

  /// Ciało opada pionowo, aż coś dotknie podłogi lub siedziska (uniesienie tylko bez krzesła).
  _J _drop(_J j, Pose pose) {
    if (anim.hands) return _shift(j, 0, -2.3 - j['haN']!.dy);
    final lift = hasChair ? 0.0 : pose.lift;
    return _shift(j, 0, _gap(j) - lift);
  }

  bool _touching(_J j, String k, [double eps = _eps]) {
    final v = j[k]!;
    return (_supportY(k, v.dx) - (v.dy + Body.thickness(k))).abs() <= eps;
  }

  bool planted(String c, int i) {
    final a = ends[c];
    return a != null && a[i] != null && a[(i + 1) % a.length] != null;
  }

  /// Gdzie ma być dłoń/stopa c w przejściu i → i+1 (postęp e); null = swobodnie.
  Offset? target(String c, int i, double e, [Offset? raw]) {
    final anc = ends[c];
    if (anc == null) return null;
    final n = anc.length;
    final a = anc[i], b = anc[(i + 1) % n];
    if (a == null && b == null) return null;
    final k = 0.5 - math.cos(math.pi * e) / 2;
    if (a != null && b != null) {
      final dist = _hyp(a, b);
      var y = a.dy + (b.dy - a.dy) * e;
      // przestawienie: krok łukiem zamiast sunięcia po podłodze
      if (dist > 0.03) y -= math.min(0.25, 0.4 * dist) * math.sin(math.pi * e);
      return Offset(a.dx + (b.dx - a.dx) * e, y);
    }
    if (raw == null) return a ?? b;
    double x, y, dist;
    if (a != null) {
      // oderwanie: z punktu oparcia do ruchu z pozy
      x = a.dx + (raw.dx - a.dx) * k;
      y = a.dy + (raw.dy - a.dy) * k;
      dist = (raw.dx - a.dx).abs();
    } else {
      // lądowanie
      x = raw.dx + (b!.dx - raw.dx) * k;
      y = raw.dy + (b.dy - raw.dy) * k;
      dist = (raw.dx - b.dx).abs();
    }
    if (dist > 0.03) y -= math.min(0.25, 0.4 * dist) * math.sin(math.pi * e);
    return Offset(x, y);
  }

  /// Poza i położenia stawów w chwili [seconds].
  (Pose, Joints) frameAt(double seconds, {double speed = 1}) {
    final pose = anim.at(seconds, speed: speed);
    final base = Joints.of(pose);
    Joints out(_J p) => Joints(p, base.front, base.back, base.headDir,
        kneesBack: base.kneesBack, z: base.z, fold: base.fold, rot: base.rot);
    if (pivot == null) return (pose, out(_drop(base.p, pose)));
    final (i, e) = anim.phase(seconds, speed: speed);
    final pv = seg[i];
    final w = world[i][pv]!;
    var j = _shift(base.p, w.dx - base.p[pv]!.dx, w.dy - base.p[pv]!.dy);
    final lift = hasChair ? 0.0 : pose.lift;
    if (lift != 0) {
      j = _shift(j, 0, -lift);
    } else if (ends.isNotEmpty && keys.length > 1) {
      for (final c in ends.keys) {
        final tgt = target(c, i, e, j[c]);
        if (tgt == null) continue;
        final (root, mid, ank, l1, l2) = _ends[c]!;
        if (ank != null) {
          // stopa: palce na miejscu, stopa pod tym samym kątem co w pozie
          final f = j[c]! - j[ank]!;
          final (m, e2) = ik2(j[root]!, j[mid]!, tgt - f, l1, l2, back: pose.back);
          j[mid] = m;
          j[ank] = e2;
          j[c] = e2 + f;
        } else {
          final (m, e2) = ik2(j[root]!, j[mid]!, tgt, l1, l2, back: pose.back, arm: true);
          j[mid] = m;
          j[c] = e2;
        }
      }
      _liftFreeLimbs(j, pose, i);
    }
    // nic nie może wejść w podłogę ani w siedzisko
    final g = _gap(j);
    if (g < -0.002) j = _shift(j, 0, g);
    return (pose, out(j));
  }

  /// Wolna noga/ręka, która w przejściu weszłaby w podłogę/siedzisko — obrót w biodrze/barku w górę.
  void _liftFreeLimbs(_J j, Pose pose, int i) {
    for (final MapEntry(key: c, value: limb) in _ends.entries) {
      if (c == seg[i] || planted(c, i)) continue;
      if (pose.ab[_limbAb[c]!] != 0 || (c.startsWith('to') && pose.kr.any((a) => a != 0))) continue;
      final (root, mid, ank, _, _) = limb;
      final pts = [mid, if (ank != null) ank, c];
      double pen(_J q) =>
          pts.map((k) => q[k]!.dy + Body.thickness(k) - _supportY(k, q[k]!.dx)).reduce(math.max);
      if (pen(j) <= 0.003) continue;
      final r = j[root]!;
      _J rot(double deg) {
        final ca = math.cos(deg * math.pi / 180), sa = math.sin(deg * math.pi / 180);
        final q = Map.of(j);
        for (final k in pts) {
          final x = j[k]!.dx - r.dx, y = j[k]!.dy - r.dy;
          q[k] = Offset(r.dx + x * ca - y * sa, r.dy + x * sa + y * ca);
        }
        return q;
      }

      search:
      for (var step = 1; step <= 120; step++) {
        for (final sg in const [1, -1]) {
          final q = rot(sg * step.toDouble());
          if (pen(q) <= -0.02) {
            // z zapasem — kończyna przechodzi nad podłogą, nie szoruje
            for (final k in pts) {
              j[k] = q[k]!;
            }
            break search;
          }
        }
      }
    }
  }

  /// Najgłębsze wejście ciała w rekwizyt (m) — do testów.
  double penetration(Joints jj) {
    const segs = [
      ('hip', 'neck', .1), ('neck', 'head', .1), ('hpN', 'knN', .07), ('knN', 'anN', .05), ('hpF', 'knF', .07),
      ('knF', 'anF', .05), ('anN', 'toN', .035), ('anF', 'toF', .035), ('shN', 'elN', .045), ('elN', 'haN', .04),
      ('shF', 'elF', .045), ('elF', 'haF', .04),
    ];
    final j = jj.p;
    final pts = <(Offset, double)>[
      for (final (a, b, r) in segs)
        for (var i = 0; i <= 8; i++) (Offset.lerp(j[a]!, j[b]!, i / 8)!, r),
      (j['head']!, 0.1),
    ];
    final pv = pivot;
    final soft = pv != null && !_ends.containsKey(pv) ? j[pv] : null;
    var worst = 0.0;
    for (final p in props) {
      for (final (v, r) in pts) {
        double d;
        if (p.type == 'chair') {
          d = [v.dx - (p.rect.left - r), (p.rect.right + r) - v.dx, v.dy - (p.rect.top - r)].reduce(math.min);
          // miejsce oparcia (łopatki na krawędzi ławki) może się lekko „wcisnąć”
          if (soft != null && _hyp(v, soft) < 0.15) d -= 0.04;
        } else if (p.type == 'wall') {
          d = math.min(v.dx - (p.rect.left - r), (p.rect.right + r) - v.dx);
        } else {
          continue;
        }
        worst = math.max(worst, d);
      }
    }
    return worst;
  }
}
