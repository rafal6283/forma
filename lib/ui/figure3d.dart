import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/figure.dart';
import 'technique.dart';
import 'theme.dart';

/// Punkt w przestrzeni: x w prawo, y w dół (podłoga y = 0), z do widza (w widoku z boku).
class V3 {
  final double x, y, z;
  const V3(this.x, this.y, this.z);
  V3 operator +(V3 o) => V3(x + o.x, y + o.y, z + o.z);
  V3 operator -(V3 o) => V3(x - o.x, y - o.y, z - o.z);
  V3 operator *(double k) => V3(x * k, y * k, z * k);
  double dot(V3 o) => x * o.x + y * o.y + z * o.z;
  double get length => math.sqrt(x * x + y * y + z * z);
  V3 get unit {
    final l = length;
    return l < 1e-9 ? const V3(0, -1, 0) : this * (1 / l);
  }

  V3 cross(V3 o) => V3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  static V3 lerp(V3 a, V3 b, double t) => a + (b - a) * t;
}

/// Stawy 2D → 3D. Pozy z boku: kończyny bliższe/dalsze rozsunięte na szerokość barków i bioder.
/// Pozy z przodu: płaszczyzna czołowa, palce stóp do widza. Stawy barkowe nieco poniżej podstawy szyi.
/// Ta sama geometria co tool/render3d.py (tam podgląd i strojenie).
Map<String, V3> lift3d(Joints j) {
  final out = <String, V3>{};
  j.p.forEach((k, v) {
    var z = 0.0;
    if (!j.front && (k.endsWith('N') || k.endsWith('F'))) {
      final arm = k.startsWith('sh') || k.startsWith('el') || k.startsWith('ha');
      z = (k.endsWith('N') ? 1 : -1) * (arm ? Body.shoulderW : Body.hipW + 0.01);
    }
    out[k] = V3(v.dx, v.dy, z);
  });
  if (j.front) {
    for (final sd in ['N', 'F']) {
      final an = out['an$sd']!, to = out['to$sd']!;
      out['to$sd'] = V3(an.x + (to.x - an.x) * 0.6, to.y, 0.12);
    }
  }
  final drop = (out['neck']! - out['hip']!).unit * -0.055;
  for (final sd in ['N', 'F']) {
    for (final k in ['sh', 'el', 'ha']) {
      out['$k$sd'] = out['$k$sd']! + drop;
    }
  }
  return out;
}

/// Kamera: obrót wokół pionowej osi sceny (yaw), lekki widok z góry (pitch), perspektywa.
class Cam {
  final double yaw, pitch, cx, cz, dist;
  late final double _cy = math.cos(yaw), _sy = math.sin(yaw), _cp = math.cos(pitch), _sp = math.sin(pitch);
  Cam(this.yaw, this.pitch, this.cx, this.cz, {this.dist = 4.5});

  /// (punkt na płaszczyźnie obrazu w metrach, głębia — większa = bliżej, skala perspektywy)
  (Offset, double, double) project(V3 p) {
    final dx = p.x - cx, dz = p.z - cz;
    final x1 = dx * _cy + dz * _sy;
    final z1 = -dx * _sy + dz * _cy;
    final y2 = p.y * _cp + z1 * _sp;
    final z2 = z1 * _cp - p.y * _sp;
    final k = dist / (dist - z2);
    return (Offset(x1 * k, y2 * k), z2, k);
  }
}

/// Rekwizyty sceny w układzie 3D.
class Prop3 {
  final String type; // chair / wall / bar
  final Rect rect; // jak w widoku 2D
  const Prop3(this.type, this.rect);
}

/// Profil kończyny: (t, promień, wypukłość z przodu, wypukłość z tyłu) — brzuśce mięśni.
typedef _Prof = List<(double, double, double, double)>;

const _armUp = <(double, double, double, double)>[(0, .056, 0, 0), (.35, .053, .009, .01), (.75, .045, .004, .003), (1, .04, 0, 0)];
const _armLo = <(double, double, double, double)>[(0, .043, 0, 0), (.22, .045, .005, .005), (1, .029, 0, 0)];
const _legUp = <(double, double, double, double)>[(0, .094, 0, 0), (.3, .089, .012, .007), (.75, .07, .005, .004), (1, .055, 0, 0)];
const _legLo = <(double, double, double, double)>[(0, .055, 0, 0), (.25, .052, .002, .019), (.62, .044, 0, .007), (1, .036, 0, 0)];
const _neck = <(double, double, double, double)>[(0, .046, 0, 0), (1, .04, 0, 0)];
const _shoe = <(double, double, double, double)>[(0, .044, 0, 0), (.3, .046, 0, 0), (1, .034, 0, 0)];
const _sole = <(double, double, double, double)>[(0, .04, 0, 0), (1, .032, 0, 0)];
const _handle = <(double, double, double, double)>[(0, .016, 0, 0), (1, .016, 0, 0)];
const _plate = <(double, double, double, double)>[(0, .045, 0, 0), (1, .045, 0, 0)];
const _barP = <(double, double, double, double)>[(0, .022, 0, 0), (1, .022, 0, 0)];

/// Przekroje tułowia: (t wzdłuż biodro→szyja, połowa szerokości, przód, tył).
const _torso = <(double, double, double, double)>[
  (-0.1, .150, .088, .112),
  (0.12, .146, .086, .102),
  (0.42, .122, .084, .074),
  (0.70, .154, .118, .086),
  (0.86, .200, .094, .088),
  (1.0, .075, .05, .05),
];

List<double> _prof(_Prof p, double t) {
  for (var i = 0; i < p.length - 1; i++) {
    final (t0, r0, f0, b0) = p[i];
    final (t1, r1, f1, b1) = p[i + 1];
    if (t <= t1) {
      var f = t1 > t0 ? (t - t0) / (t1 - t0) : 0.0;
      f = f * f * (3 - 2 * f);
      return [r0 + (r1 - r0) * f, f0 + (f1 - f0) * f, b0 + (b1 - b0) * f];
    }
  }
  final (_, r, f, b) = p.last;
  return [r, f, b];
}

/// Otoczka wypukła (monotone chain).
List<Offset> _hull(List<Offset> pts) {
  final ps = [...pts]..sort((a, b) => a.dx != b.dx ? a.dx.compareTo(b.dx) : a.dy.compareTo(b.dy));
  if (ps.length < 3) return ps;
  double cr(Offset o, Offset a, Offset b) => (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);
  List<Offset> half(Iterable<Offset> src) {
    final h = <Offset>[];
    for (final p in src) {
      while (h.length >= 2 && cr(h[h.length - 2], h.last, p) <= 0) {
        h.removeLast();
      }
      h.add(p);
    }
    return h;
  }

  final lo = half(ps), up = half(ps.reversed);
  return [...lo.sublist(0, lo.length - 1), ...up.sublist(0, up.length - 1)];
}

/// Malarz realistycznej postaci 3D: kończyny z brzuścami mięśni, tułów z przekrojów (klatka, talia, miednica),
/// głowa z żuchwą, uszami i włosami, dłonie, buty z podeszwą, ubranie, światłocień i cienie na podłodze.
/// Części sortowane po głębi; kamera obracana gestem.
class Figure3DPainter extends CustomPainter {
  final Joints j;
  final Cam cam;
  final Rect bounds; // kadr w układzie obrazu kamery (metry)
  final bool floor, hands;
  final String? hold;
  final List<Prop3> props;
  final double breath;
  final Map<String, double> glow;

  Figure3DPainter({
    required this.j,
    required this.cam,
    required this.bounds,
    this.floor = true,
    this.hands = false,
    this.hold,
    this.props = const [],
    this.breath = 0,
    this.glow = const {},
  });

  static const skin = Color(0xFFE8BE9C), shirt = Color(0xFFFF6A3D), shorts = Color(0xFF343A4E);
  static const shoe = Color(0xFFF0F2F6), sole = Color(0xFF40454F), hair = Color(0xFF3A2A20), eye = Color(0xFF281E1A);
  static const _light = Offset(-0.45, -0.89);

  late Canvas _c;
  late double _s;
  late Offset _o;

  (Offset, double, double) _pr(V3 p) {
    final (o, z, k) = cam.project(p);
    return (o * _s + _o, z, k);
  }

  Color _tint(Color c, double z) {
    final t = ((0.35 - z) / 0.7).clamp(0.0, 1.0);
    return Color.lerp(c, Colors.black, 0.25 * t)!;
  }

  Paint _shade(Color base, Offset a, Offset b, double r) {
    var u = b - a;
    u = u.distance < 1e-6 ? const Offset(0, -1) : u / u.distance;
    var n = Offset(-u.dy, u.dx);
    if (n.dx * _light.dx + n.dy * _light.dy < 0) n = -n;
    final m = (a + b) / 2;
    return Paint()
      ..isAntiAlias = true
      ..shader = ui.Gradient.linear(
        m + n * r,
        m - n * r,
        [Color.lerp(base, Colors.white, 0.18)!, base, Color.lerp(base, Colors.black, 0.32)!],
        const [0, 0.42, 1],
      );
  }

  final _edge = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..color = Colors.black.withValues(alpha: 0.22);

  /// Przód kończyny (prostopadle do niej): z boku w płaszczyźnie ruchu, z przodu — do widza.
  V3 _anterior(V3 d) {
    if (j.front) {
      const f = V3(0, 0, 1);
      return (f - d * f.dot(d)).unit;
    }
    final a = V3(d.y, -d.x, 0);
    return j.back ? a * -1 : a;
  }

  /// Kontur kończyny z profilem mięśni; zwraca (ścieżka, początek, koniec, promień).
  (Path, Offset, Offset, double) _limbPath(V3 a, V3 b, _Prof prof, V3 front,
      {double grow = 0, double t0 = 0, double t1 = 1}) {
    final (pa, _, ka) = _pr(a);
    final (pb, _, kb) = _pr(b);
    var u = pb - pa;
    u = u.distance < 1e-6 ? const Offset(0, -1) : u / u.distance;
    final nrm = Offset(-u.dy, u.dx);
    final mid = V3.lerp(a, b, 0.5);
    final (fp, _, _) = _pr(mid + front * 0.1);
    final (mp, _, km) = _pr(mid);
    final fv = (fp - mp) / (0.1 * _s * km);
    final side = fv.dx * nrm.dx + fv.dy * nrm.dy;
    const n = 14;
    final left = <Offset>[], right = <Offset>[];
    for (var i = 0; i <= n; i++) {
      final t = t0 + (t1 - t0) * i / n;
      final p = _prof(prof, t);
      final k = ka + (kb - ka) * t;
      final c = Offset.lerp(pa, pb, t)!;
      final rl = (p[0] + grow + (side > 0 ? p[1] : p[2]) * side.abs()) * _s * k;
      final rr = (p[0] + grow + (side > 0 ? p[2] : p[1]) * side.abs()) * _s * k;
      left.add(c + nrm * rl);
      right.add(c - nrm * rr);
    }
    final r0 = (_prof(prof, t0)[0] + grow) * _s * (ka + (kb - ka) * t0);
    final r1 = (_prof(prof, t1)[0] + grow) * _s * (ka + (kb - ka) * t1);
    final ps = Offset.lerp(pa, pb, t0)!, pe = Offset.lerp(pa, pb, t1)!;
    final pts = <Offset>[
      ...left,
      for (var i = 1; i < 8; i++) pe + u * (r1 * math.sin(math.pi * i / 8)) + nrm * (r1 * math.cos(math.pi * i / 8)),
      ...right.reversed,
      for (var i = 1; i < 8; i++) ps + u * (-r0 * math.sin(math.pi * i / 8)) + nrm * (-r0 * math.cos(math.pi * i / 8)),
    ];
    return (Path()..addPolygon(pts, true), ps, pe, math.max(r0, r1));
  }

  void _limb(V3 a, V3 b, _Prof prof, V3 front, Color col, double z,
      {double grow = 0, double t0 = 0, double t1 = 1, bool edge = true, String? tag}) {
    final (path, pa, pe, r) = _limbPath(a, b, prof, front, grow: grow, t0: t0, t1: t1);
    _c.drawPath(path, _shade(_tint(col, z), pa, pe, r * 1.2));
    final g = tag == null ? 0.0 : (glow[tag] ?? 0);
    if (g > 0.02) _c.drawPath(path, Paint()..color = glowColor(0.55 * g));
    if (edge) _c.drawPath(path, _edge);
  }

  void _ball(V3 p, double r, Color col, {bool edge = true}) {
    final (c, z, k) = _pr(p);
    final rr = r * _s * k;
    final base = _tint(col, z);
    _c.drawCircle(
      c,
      rr,
      Paint()
        ..shader = ui.Gradient.radial(
          c + _light * (rr * 0.45),
          rr * 1.5,
          [Color.lerp(base, Colors.white, 0.2)!, base, Color.lerp(base, Colors.black, 0.32)!],
          const [0, 0.45, 1],
        ),
    );
    if (edge) _c.drawCircle(c, rr, _edge);
  }

  // ------------------------------------------------------------------ tułów
  (V3, V3, V3, V3, V3) _frame(Map<String, V3> q) {
    final hip = q['hip']!, neck = q['neck']!;
    final u = (neck - hip).unit;
    var lat = j.front ? const V3(1, 0, 0) : const V3(0, 0, 1);
    lat = (lat - u * lat.dot(u)).unit;
    V3 f;
    if (j.front) {
      f = lat.cross(u).unit;
      if (f.z < 0) f = f * -1;
    } else {
      f = V3(-u.y, u.x, 0);
      if (j.back) f = f * -1;
    }
    return (hip, neck, u, lat, f);
  }

  List<Offset> _section(Map<String, V3> q, double t, double w, double df, double db, double grow) {
    final (hip, neck, u, lat, f) = _frame(q);
    final c = hip + u * ((neck - hip).length * t);
    return [
      for (var i = 0; i < 16; i++)
        _pr(c +
                lat * ((w + grow) * math.cos(2 * math.pi * i / 16)) +
                f * (((math.sin(2 * math.pi * i / 16) > 0 ? df : db) + grow) * math.sin(2 * math.pi * i / 16)))
            .$1,
    ];
  }

  void _union(Map<String, V3> q, List<(double, double, double, double)> secs, Color col, double z,
      {double grow = 0, double g = 0}) {
    final rings = [for (final (t, w, df, db) in secs) _section(q, t, w, df, db, grow)];
    final path = Path()..fillType = PathFillType.nonZero;
    for (var i = 0; i < rings.length - 1; i++) {
      path.addPolygon(_hull([...rings[i], ...rings[i + 1]]), true);
    }
    // obrys pod spodem (2 px) — po wypełnieniu zostaje tylko zewnętrzna krawędź
    _c.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.black.withValues(alpha: 0.2));
    final (ph, _, _) = _pr(q['hip']!);
    final (pn, _, _) = _pr(q['neck']!);
    _c.drawPath(path, _shade(_tint(col, z), ph, pn, 0.17 * _s));
    if (g > 0.02) _c.drawPath(path, Paint()..color = glowColor(0.5 * g));
  }

  void _torsoDraw(Map<String, V3> q, double z) {
    final secs = [
      for (final (t, w, df, db) in _torso) (t, w, t > 0.5 ? df * (1 + 0.04 * breath) : df, db),
    ];
    final lo = [
      for (final s in secs)
        if (s.$1 <= 0.42) (s.$1 < 0.4 ? s.$1 : 0.2, s.$2, s.$3, s.$4),
    ];
    _union(q, lo, shorts, z, grow: 0.006, g: glow['pelvis'] ?? 0);
    final hi = [
      for (final s in secs)
        if (s.$1 >= 0.12) s,
    ];
    hi[0] = (0.14, hi[0].$2, hi[0].$3, hi[0].$4);
    _union(q, hi, shirt, z, g: math.max(glow['chest'] ?? 0, glow['abs'] ?? 0));
  }

  // ------------------------------------------------------------------ głowa
  void _head(Map<String, V3> q) {
    final head = q['head']!;
    final up = (head - q['neck']!).unit;
    V3 face;
    if (j.front) {
      face = const V3(0, 0, 1);
    } else {
      face = V3(-up.y, up.x, 0);
      if (j.back) face = face * -1;
    }
    final side = up.cross(face).unit;
    final (c, zc, k) = _pr(head);
    final r = 0.1 * _s * k;
    // żuchwa / broda
    _ball(head + face * 0.022 - up * 0.045, 0.062, skin, edge: false);
    // uszy po stronie widza
    for (final sg in [-1.0, 1.0]) {
      final (e, ze, ke) = _pr(head + side * (0.093 * sg));
      if (ze > zc + 0.02) {
        _c.save();
        _c.translate(e.dx, e.dy);
        _c.scale(0.55, 1);
        _c.drawCircle(Offset.zero, 0.03 * _s * ke, Paint()..color = _tint(Color.lerp(skin, Colors.black, 0.08)!, ze));
        _c.restore();
      }
    }
    _ball(head, 0.1, skin);
    // włosy: koło przesunięte ku potylicy i w górę (w rzucie), przycięte do głowy
    Offset dirv(V3 v) {
      final (p, _, _) = _pr(head + v * 0.1);
      return (p - c) / (0.1 * _s * k);
    }

    final (_, zf, _) = _pr(head + face * 0.1);
    final toward = ((zf - zc) / 0.1).clamp(-1.0, 1.0);
    final hc = c + (dirv(face * -1) * 0.6 + dirv(up) * (0.15 + 1.25 * math.max(0.0, toward))) * r;
    _c.save();
    _c.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r * 1.04)));
    _c.drawCircle(hc, r, Paint()..color = hair);
    _c.restore();
    final (nose, zn, _) = _pr(head + face * 0.1 - up * 0.012);
    if (zn > zc + 0.01) {
      _c.drawCircle(nose, r * (0.17 - 0.09 * math.max(0.0, toward)), Paint()..color = _tint(skin, zc));
    }
    for (final sg in [-1.0, 1.0]) {
      final (e, ze, _) = _pr(head + face * 0.086 + side * (0.034 * sg) + up * 0.02);
      if (ze > zc + 0.03) _c.drawCircle(e, math.max(1.2, r * 0.1), Paint()..color = eye);
    }
  }

  void _hand(V3 el, V3 ha) {
    final d = (ha - el).unit;
    _ball(ha + d * 0.02, 0.036, skin);
    _ball(ha + d * 0.055, 0.03, skin, edge: false);
  }

  void _shoe(V3 an, V3 to, double z, V3 front) {
    final d = (to - an).unit;
    final heel = an - d * 0.04, tip = to + d * 0.015;
    const down = V3(0, 0.012, 0);
    _limb(heel + down, tip + down, _sole, front, sole, z, edge: false);
    _limb(heel, tip, _shoe, front, shoe, z);
  }

  // ------------------------------------------------------------------ sprzęt i rekwizyty
  void _holds(Map<String, V3> q) {
    final hh = hold;
    if (hh == null) return;
    final lat = j.front ? const V3(1, 0, 0) : const V3(0, 0, 1);
    const metal = Color(0xFF4A5262), dark = Color(0xFF2B3040);
    if (hh == 'band') {
      final (a, _, _) = _pr(q['haN']!);
      final (b, _, _) = _pr(q['haF']!);
      _c.drawLine(a, b, Paint()
        ..color = C.accent
        ..strokeWidth = math.max(2.0, 0.018 * _s)
        ..strokeCap = StrokeCap.round);
      return;
    }
    final single = hh == 'kb' || hh == 'db1';
    for (final sd in single ? ['N'] : ['N', 'F']) {
      final ha = q['ha$sd']! + (q['ha$sd']! - q['el$sd']!).unit * 0.04;
      if (hh == 'kb') {
        _ball(ha + const V3(0, 0.1, 0), 0.075, dark);
        _limb(ha - lat * 0.04, ha + lat * 0.04, _handle, const V3(0, -1, 0), metal, 0);
      } else {
        _limb(ha - lat * 0.09, ha + lat * 0.09, _handle, const V3(0, -1, 0), metal, 0);
        _limb(ha - lat * 0.11, ha - lat * 0.06, _plate, const V3(0, -1, 0), dark, 0);
        _limb(ha + lat * 0.06, ha + lat * 0.11, _plate, const V3(0, -1, 0), dark, 0);
      }
    }
  }

  void _props(Map<String, V3> q) {
    for (final pr in props) {
      final r = pr.rect;
      switch (pr.type) {
        case 'wall':
          final pts = [
            V3(r.left, r.top, -0.9),
            V3(r.left, r.top, 0.9),
            V3(r.left, 0, 0.9),
            V3(r.left, 0, -0.9),
          ].map((v) => _pr(v).$1).toList();
          _c.drawPath(Path()..addPolygon(pts, true), Paint()..color = C.surface2.withValues(alpha: 0.85));
        case 'chair':
          const d = 0.22;
          final top = [V3(r.left, r.top, -d), V3(r.right, r.top, -d), V3(r.right, r.top, d), V3(r.left, r.top, d)];
          for (final c in top) {
            final (a, _, ka) = _pr(c);
            final (b, _, _) = _pr(V3(c.x, 0, c.z));
            _c.drawLine(
                a,
                b,
                Paint()
                  ..color = Color.lerp(C.prop, Colors.black, 0.25)!
                  ..strokeWidth = math.max(2.0, 0.03 * _s * ka));
          }
          _c.drawPath(Path()..addPolygon(top.map((v) => _pr(v).$1).toList(), true), Paint()..color = C.prop);
          final front = [top[2], top[3], top[3] + const V3(0, 0.05, 0), top[2] + const V3(0, 0.05, 0)]
              .map((v) => _pr(v).$1)
              .toList();
          _c.drawPath(Path()..addPolygon(front, true), Paint()..color = Color.lerp(C.prop, Colors.black, 0.3)!);
        case 'bar':
          final lat = j.front ? const V3(1, 0, 0) : const V3(0, 0, 1);
          final hc = q['haN']!;
          final c = V3(j.front ? (q['haN']!.x + q['haF']!.x) / 2 : hc.x, hc.y - 0.02, j.front ? hc.z : 0);
          _limb(c - lat * 0.7, c + lat * 0.7, _barP, const V3(0, -1, 0), C.prop, 0.2);
      }
    }
  }

  // ------------------------------------------------------------------ podłoga
  void _floor(Map<String, V3> q) {
    var cx = 0.0, cz = 0.0;
    for (final k in ['anN', 'anF', 'hip']) {
      cx += q[k]!.x / 3;
      cz += q[k]!.z / 3;
    }
    final disk = Path();
    for (var i = 0; i <= 48; i++) {
      final a = i / 48 * math.pi * 2;
      final (p, _, _) = _pr(V3(cx + math.cos(a) * 1.25, 0, cz + math.sin(a) * 1.25));
      i == 0 ? disk.moveTo(p.dx, p.dy) : disk.lineTo(p.dx, p.dy);
    }
    disk.close();
    final b = disk.getBounds();
    _c.save();
    _c.clipPath(disk);
    _c.translate(b.center.dx, b.center.dy);
    _c.scale(1, b.height / b.width);
    _c.drawCircle(
      Offset.zero,
      b.width / 2,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset.zero,
          b.width / 2,
          [C.surface2.withValues(alpha: 0.9), C.surface2.withValues(alpha: 0.35), C.surface2.withValues(alpha: 0)],
          const [0, 0.7, 1],
        ),
    );
    _c.restore();
    // miękkie cienie pod ciałem (światło z góry) — słabsze, gdy część ciała jest wysoko
    final blur = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    final alpha = C.light ? 0.16 : 0.32;
    for (final part in ['hip', 'neck', 'knN', 'knF', 'anN', 'anF', 'haN', 'haF', 'elN', 'elF', 'head']) {
      final v = q[part]!;
      final (c, _, k) = _pr(V3(v.x, 0, v.z));
      final lift = math.max(0.0, -v.y);
      final big = part == 'hip' || part == 'neck' || part == 'head';
      final rr = (big ? 0.13 : 0.06) * _s * k * (1 + lift * 0.3);
      _c.save();
      _c.translate(c.dx, c.dy);
      _c.scale(1, 0.35);
      _c.drawCircle(Offset.zero, rr, blur..color = Colors.black.withValues(alpha: alpha * math.max(0.15, 1 - lift * 0.6)));
      _c.restore();
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    _c = canvas;
    _s = math.min(size.width / bounds.width, size.height / bounds.height);
    _o = Offset((size.width - bounds.width * _s) / 2 - bounds.left * _s, (size.height - bounds.height * _s) / 2 - bounds.top * _s);
    final q = lift3d(j);
    if (floor && !hands) _floor(q);
    _props(q);

    double zof(List<V3> ps) => ps.fold(0.0, (a, p) => a + cam.project(p).$2) / ps.length;
    final items = <(double, void Function())>[];
    for (final sd in ['N', 'F']) {
      final sh = q['sh$sd']!, el = q['el$sd']!, ha = q['ha$sd']!;
      final hp = q['hp$sd']!, kn = q['kn$sd']!, an = q['an$sd']!, to = q['to$sd']!;
      final fA = _anterior((el - sh).unit), fF = _anterior((ha - el).unit);
      final fT = _anterior((kn - hp).unit), fS = _anterior((an - kn).unit);
      final zA = zof([sh, el]), zF = zof([el, ha]), zT = zof([hp, kn]), zS = zof([kn, an]), zFt = zof([an, to]);
      items
        ..add((zS, () => _limb(kn, an, _legLo, fS, skin, zS, tag: 'shin')))
        ..add((
          zT + 0.001,
          () {
            _limb(hp, kn, _legUp, fT, skin, zT, tag: 'thigh');
            _limb(hp, kn, _legUp, fT, shorts, zT, grow: 0.007, t1: 0.42, tag: 'pelvis');
          }
        ))
        ..add((zFt + 0.002, () => _shoe(an, to, zFt, fS)))
        ..add((
          zF + 0.003,
          () {
            _limb(el, ha, _armLo, fF, skin, zF, tag: 'forearm');
            _hand(el, ha);
          }
        ))
        ..add((
          zA + 0.004,
          () {
            _limb(sh, el, _armUp, fA, skin, zA, tag: 'upperArm');
            _limb(sh, el, _armUp, fA, shirt, zA, grow: 0.005, t1: 0.38, tag: 'shoulder');
          }
        ));
    }
    final zt = zof([q['hip']!, q['neck']!]);
    items.add((
      zt,
      () {
        _limb(q['neck']!, V3.lerp(q['neck']!, q['head']!, 0.55), _neck, const V3(0, 0, 1), skin, zt, edge: false);
        _torsoDraw(q, zt);
      }
    ));
    items.add((zof([q['head']!]) + 0.002, () => _head(q)));
    items.add((zof([q['haN']!]) + 0.01, () => _holds(q)));
    items.sort((a, b) => a.$1.compareTo(b.$1));
    for (final (_, f) in items) {
      f();
    }
  }

  @override
  bool shouldRepaint(Figure3DPainter old) => true;
}

/// Kadr dla danego kąta kamery: rzut wszystkich próbek animacji (żeby postać nie „skakała”).
Rect frame3d(List<Joints> samples, Cam cam, {bool floor = true}) {
  Rect? r;
  for (final j in samples) {
    final q = lift3d(j);
    for (final v in q.values) {
      final (o, _, k) = cam.project(v);
      final rr = Rect.fromCircle(center: o, radius: 0.11 * k);
      r = r == null ? rr : r.expandToInclude(rr);
    }
    if (floor) {
      for (final v in [q['anN']!, q['anF']!]) {
        for (final dx in [-0.5, 0.5]) {
          final (o, _, _) = cam.project(V3(v.x + dx, 0, v.z));
          r = r!.expandToInclude(Rect.fromCircle(center: o, radius: 0.02));
        }
      }
    }
  }
  r ??= const Rect.fromLTWH(-1, -2, 2, 2);
  final w = math.max(r.width, 1.2), h = math.max(r.height, 1.3);
  return Rect.fromCenter(center: r.center, width: w + 0.35, height: h + 0.3);
}
