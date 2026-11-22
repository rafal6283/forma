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
    out[k] = V3(v.dx, v.dy, z + (j.z[k] ?? 0));
  });
  if (j.front && j.kneesBack) {
    // golenie zgięte do tyłu, za płaszczyznę ciała
    for (final sd in ['N', 'F']) {
      final kn = out['kn$sd']!;
      out['an$sd'] = V3(kn.x, kn.y + 0.01, -Body.shin * 0.97);
      out['to$sd'] = V3(kn.x, kn.y - 0.03, -Body.shin - Body.foot * 0.5);
    }
  } else if (j.front) {
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

/// Część ciała w kolejce malowania: średnia głębokość, kapsuły (odcinek 3D + promień w m), rysowanie.
class _Item {
  final double z;
  final List<(V3, V3, double)> caps;
  final void Function() draw;
  final bool torso;
  _Item(this.z, this.caps, this.draw, {this.torso = false});
}

/// Fragment ciała do malowania.
class _Seg {
  final Path path;
  final Paint paint;
  final double glow;
  const _Seg(this.path, this.paint, this.glow);
}

/// Rekwizyty sceny w układzie 3D.
class Prop3 {
  final String type; // chair / wall / bar
  final Rect rect; // jak w widoku 2D
  const Prop3(this.type, this.rect);
}

/// Profil kończyny: (t, promień, wypukłość z przodu, wypukłość z tyłu) — brzuśce mięśni.
typedef _Prof = List<(double, double, double, double)>;

const _armUp = <(double, double, double, double)>[(0, .05, 0, 0), (.3, .048, .008, .011), (.72, .042, .004, .004), (1, .038, 0, 0)];
const _armLo = <(double, double, double, double)>[(0, .04, 0, 0), (.22, .043, .006, .005), (.7, .033, .001, .001), (1, .027, 0, 0)];
const _legUp = <(double, double, double, double)>[(0, .086, 0, 0), (.3, .081, .013, .008), (.72, .065, .007, .004), (1, .052, 0, 0)];
const _legLo = <(double, double, double, double)>[
  (0, .051, 0, 0),
  (.28, .05, .002, .02),
  (.62, .041, 0, .008),
  (.92, .032, 0, 0),
  (1, .034, 0, 0),
];
const _knee = <(double, double, double, double)>[(0, .052, 0, 0), (1, .05, 0, 0)];
const _handP = <(double, double, double, double)>[(0, .03, 0, 0), (.45, .038, 0, 0), (1, .028, 0, 0)];
const _neck = <(double, double, double, double)>[(0, .052, 0, 0), (1, .044, 0, 0)];
const _shoeProf = <(double, double, double, double)>[(0, .046, 0, 0), (.3, .05, 0, 0), (.75, .043, 0, 0), (1, .032, 0, 0)];
const _sole = <(double, double, double, double)>[(0, .047, 0, 0), (.3, .051, 0, 0), (1, .036, 0, 0)];
const _handle = <(double, double, double, double)>[(0, .016, 0, 0), (1, .016, 0, 0)];
const _plate = <(double, double, double, double)>[(0, .045, 0, 0), (1, .045, 0, 0)];
const _barP = <(double, double, double, double)>[(0, .022, 0, 0), (1, .022, 0, 0)];

/// Przekroje tułowia: (t wzdłuż biodro→szyja, połowa szerokości, przód, tył) — miednica, talia, klatka, barki, kark.
const _torso = <(double, double, double, double)>[
  (-0.1, .178, .078, .1),
  (0.12, .176, .082, .094),
  (0.42, .124, .08, .07),
  (0.66, .15, .112, .084),
  (0.84, .19, .1, .09),
  (0.94, .15, .07, .078),
  (1.0, .07, .05, .05),
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
        [
          Color.lerp(base, Colors.black, 0.22)!, // odbite światło przy krawędzi
          Color.lerp(base, Colors.white, 0.24)!,
          base,
          Color.lerp(base, Colors.black, 0.4)!,
          Color.lerp(base, Colors.black, 0.32)!,
        ],
        const [0, 0.12, 0.45, 0.85, 1],
      );
  }

  static const _outW = 2.2;

  /// Obrys rysowany pod wypełnieniem — po zamalowaniu zostaje tylko zewnętrzna krawędź (bez szwów w stawach).
  void _outline(List<Path> paths, {double a = 0.3}) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _outW
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.black.withValues(alpha: a);
    for (final path in paths) {
      _c.drawPath(path, p);
    }
  }

  /// Fragment ciała gotowy do malowania: kontur i cieniowanie.
  _Seg _seg(V3 a, V3 b, _Prof prof, V3 front, Color col, double z, {double grow = 0, double t1 = 1, String? tag}) {
    final (path, pa, pe, r) = _limbPath(a, b, prof, front, grow: grow, t1: t1);
    return _Seg(path, _shade(_tint(col, z), pa, pe, r * 1.2), tag == null ? 0 : (glow[tag] ?? 0));
  }

  void _paintSeg(_Seg s) {
    _c.drawPath(s.path, s.paint);
    if (s.glow > 0.02) _c.drawPath(s.path, Paint()..color = glowColor(0.55 * s.glow));
  }

  /// Noga: udo, kolano i łydka jednym konturem, nogawka spodenek, but.
  void _leg(V3 hp, V3 kn, V3 an, V3 to, V3 fT, V3 fS, double z, double zf) {
    final thigh = _seg(hp, kn, _legUp, fT, skin, z, tag: 'thigh');
    final shin = _seg(kn, an, _legLo, fS, skin, z, tag: 'shin');
    final knee = _seg(V3.lerp(kn, hp, 0.12), V3.lerp(kn, an, 0.12), _knee, fT, skin, z);
    _outline([thigh.path, shin.path, knee.path]);
    _paintSeg(shin);
    _paintSeg(knee);
    _paintSeg(thigh);
    final sh = _seg(hp, kn, _legUp, fT, shorts, z, grow: 0.008, t1: 0.4, tag: 'pelvis');
    _outline([sh.path], a: 0.25);
    _paintSeg(sh);
    _shoe(an, to, zf, fS);
  }

  /// Udo z kolanem i nogawką – gdy udo i goleń leżą na różnej głębokości (np. golenie za ciałem
  /// w klęku), każda część jest sortowana osobno, żeby stopa nie „prześwitywała” przez tułów.
  void _thighOnly(V3 hp, V3 kn, V3 an, V3 fT, double z) {
    final thigh = _seg(hp, kn, _legUp, fT, skin, z, tag: 'thigh');
    final knee = _seg(V3.lerp(kn, hp, 0.12), V3.lerp(kn, an, 0.12), _knee, fT, skin, z);
    _outline([thigh.path, knee.path]);
    _paintSeg(knee);
    _paintSeg(thigh);
    final sh = _seg(hp, kn, _legUp, fT, shorts, z, grow: 0.008, t1: 0.4, tag: 'pelvis');
    _outline([sh.path], a: 0.25);
    _paintSeg(sh);
  }

  void _shinOnly(V3 hp, V3 kn, V3 an, V3 to, V3 fT, V3 fS, double z, double zf) {
    final shin = _seg(kn, an, _legLo, fS, skin, z, tag: 'shin');
    final knee = _seg(V3.lerp(kn, hp, 0.12), V3.lerp(kn, an, 0.12), _knee, fT, skin, z);
    _outline([shin.path, knee.path]);
    _paintSeg(shin);
    _paintSeg(knee);
    _shoe(an, to, zf, fS);
  }

  void _upperArmOnly(V3 sh, V3 el, V3 fA, double z) {
    final up = _seg(sh, el, _armUp, fA, skin, z, tag: 'upperArm');
    _outline([up.path]);
    _paintSeg(up);
    _ball(el, 0.034, skin, edge: false);
    final sl = _seg(sh, el, _armUp, fA, shirt, z, grow: 0.004, t1: 0.34, tag: 'shoulder');
    _outline([sl.path], a: 0.25);
    _paintSeg(sl);
  }

  void _forearmOnly(V3 el, V3 ha, V3 fF, double z, double facing) {
    final lo = _seg(el, ha, _armLo, fF, skin, z, tag: 'forearm');
    var d = (ha - el).unit;
    if (ha.y > -0.07 && d.y > 0.5) d = j.front ? const V3(0, 0, 1) : V3(facing >= 0 ? 1 : -1, 0, 0);
    final hand = _seg(ha - d * 0.005, ha + d * 0.095, _handP, fF, skin, z);
    _outline([lo.path, hand.path]);
    _paintSeg(hand);
    _paintSeg(lo);
    _ball(ha + d * 0.035 + fF * 0.026, 0.019, skin, edge: false);
    _ball(el, 0.033, skin, edge: false);
  }

  /// Ręka: ramię, przedramię i dłoń jednym konturem, kciuk, rękaw.
  void _arm(V3 sh, V3 el, V3 ha, V3 fA, V3 fF, double z, double facing) {
    final up = _seg(sh, el, _armUp, fA, skin, z, tag: 'upperArm');
    final lo = _seg(el, ha, _armLo, fF, skin, z, tag: 'forearm');
    var d = (ha - el).unit;
    // dłoń oparta o podłogę: płasko, palcami do przodu
    if (ha.y > -0.07 && d.y > 0.5) d = j.front ? const V3(0, 0, 1) : V3(facing >= 0 ? 1 : -1, 0, 0);
    final hand = _seg(ha - d * 0.005, ha + d * 0.095, _handP, fF, skin, z);
    _outline([up.path, lo.path, hand.path]);
    _paintSeg(hand);
    _paintSeg(lo);
    _paintSeg(up);
    _ball(ha + d * 0.035 + fF * 0.026, 0.019, skin, edge: false);
    final sl = _seg(sh, el, _armUp, fA, shirt, z, grow: 0.004, t1: 0.34, tag: 'shoulder');
    _outline([sl.path], a: 0.25);
    _paintSeg(sl);
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
      // przód klatki: do widza, a przy skłonie obrócony w dół razem z tułowiem
      final fr = j.fold * math.pi / 180;
      final f0 = V3(0, math.sin(fr), math.cos(fr));
      f = (f0 - u * f0.dot(u)).unit;
    } else {
      f = V3(-u.y, u.x, 0);
      if (j.back) f = f * -1;
    }
    return (hip, neck, u, lat, f);
  }

  List<Offset> _section(Map<String, V3> q, double t, double w, double df, double db, double grow) {
    var (hip, neck, u, lat, f) = _frame(q);
    // skręt barków: górne pierścienie tułowia obracają się stopniowo od pasa w górę
    final rot = j.rot * math.pi / 180 * ((t - 0.25) / 0.6).clamp(0.0, 1.0);
    if (rot != 0) {
      (lat, f) = (lat * math.cos(rot) + f * math.sin(rot), f * math.cos(rot) - lat * math.sin(rot));
    }
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
          ..strokeWidth = _outW
          ..strokeJoin = StrokeJoin.round
          ..color = Colors.black.withValues(alpha: 0.3));
    final (ph, _, _) = _pr(q['hip']!);
    final (pn, _, _) = _pr(q['neck']!);
    _c.drawPath(path, _shade(_tint(col, z), ph, pn, 0.17 * _s));
    if (g > 0.02) _c.drawPath(path, Paint()..color = glowColor(0.5 * g));
  }

  void _torsoDraw(Map<String, V3> q, double z) {
    final secs = [
      for (final (t, w, df, db) in _torso) (t, w, t > 0.5 ? df * (1 + 0.04 * breath) : df, db),
    ];
    (double, double, double, double) at(double t) {
      for (var i = 0; i < secs.length - 1; i++) {
        final a = secs[i], b = secs[i + 1];
        if (a.$1 <= t && t <= b.$1) {
          final f = (t - a.$1) / (b.$1 - a.$1);
          return (t, a.$2 + (b.$2 - a.$2) * f, a.$3 + (b.$3 - a.$3) * f, a.$4 + (b.$4 - a.$4) * f);
        }
      }
      return secs.last;
    }

    // spodenki od pośladków do pasa; koszulka nachodzi na pas
    _pelvisDraw(q, z, secs, at);
    _chestDraw(q, z, secs, at);
  }

  List<(double, double, double, double)> _secs() => [
        for (final (t, w, df, db) in _torso) (t, w, t > 0.5 ? df * (1 + 0.04 * breath) : df, db),
      ];

  (double, double, double, double) _secAt(List<(double, double, double, double)> secs, double t) {
    for (var i = 0; i < secs.length - 1; i++) {
      final a = secs[i], b = secs[i + 1];
      if (a.$1 <= t && t <= b.$1) {
        final f = (t - a.$1) / (b.$1 - a.$1);
        return (t, a.$2 + (b.$2 - a.$2) * f, a.$3 + (b.$3 - a.$3) * f, a.$4 + (b.$4 - a.$4) * f);
      }
    }
    return secs.last;
  }

  void _pelvisDraw(Map<String, V3> q, double z, List<(double, double, double, double)> secs,
          (double, double, double, double) Function(double) at) =>
      _union(q, [...secs.where((s) => s.$1 < 0.3), at(0.3)], shorts, z, grow: 0.006, g: glow['pelvis'] ?? 0);

  void _chestDraw(Map<String, V3> q, double z, List<(double, double, double, double)> secs,
          (double, double, double, double) Function(double) at) =>
      _union(q, [at(0.22), ...secs.where((s) => s.$1 > 0.22)], shirt, z, g: math.max(glow['chest'] ?? 0, glow['abs'] ?? 0));

  // ------------------------------------------------------------------ głowa
  void _head(Map<String, V3> q) {
    final head = q['head']!;
    final up = (head - q['neck']!).unit;
    V3 face;
    if (j.front) {
      final fr = j.fold * math.pi / 180;
      final f0 = V3(0, math.sin(fr), math.cos(fr));
      face = (f0 - up * f0.dot(up)).unit;
    } else {
      face = V3(-up.y, up.x, 0);
      if (j.back) face = face * -1;
    }
    if (j.rot != 0) {
      var lat0 = j.front ? const V3(1, 0, 0) : const V3(0, 0, 1);
      lat0 = (lat0 - up * lat0.dot(up)).unit;
      final r = j.rot * 0.6 * math.pi / 180;
      face = (face * math.cos(r) - lat0 * math.sin(r)).unit;
    }
    final side = up.cross(face).unit;
    final (c, zc, k) = _pr(head);
    final r = 0.1 * _s * k;
    final (_, zf, _) = _pr(head + face * 0.1);
    final toward = ((zf - zc) / 0.1).clamp(-1.0, 1.0);
    (Offset, double, double) at(double f, double sd, double u) => _pr(head + face * f + side * sd + up * u);

    // szyja
    final zt = zc - 0.001;
    _paintSeg(_seg(q['neck']!, V3.lerp(q['neck']!, head, 0.55), _neck, const V3(0, 0, 1), skin, zt));
    // obrys czaszki z żuchwą pod spodem
    final jaw = head + face * 0.03 - up * 0.052;
    final (jc, _, jk) = _pr(jaw);
    _outline([
      Path()
        ..addOval(Rect.fromCircle(center: c, radius: r))
        ..addOval(Rect.fromCircle(center: jc, radius: 0.064 * _s * jk)),
    ]);
    // uszy po stronie widza
    for (final sg in [-1.0, 1.0]) {
      final (e, ze, ke) = at(-0.005, 0.094 * sg, -0.01);
      if (ze > zc + 0.02) {
        _c.save();
        _c.translate(e.dx, e.dy);
        _c.scale(0.6, 1);
        _c.drawCircle(Offset.zero, 0.03 * _s * ke, Paint()..color = _tint(Color.lerp(skin, Colors.black, 0.1)!, ze));
        _c.restore();
      }
    }
    _ball(jaw, 0.064, skin, edge: false);
    _ball(head, 0.1, skin, edge: false);
    // włosy: czapa przesunięta ku potylicy i w górę, z połyskiem, przycięta do nieco większej głowy
    Offset dirv(V3 v) {
      final (p, _, _) = _pr(head + v * 0.1);
      return (p - c) / r;
    }

    final hc = c + (dirv(face * -1) * 0.55 + dirv(up) * (0.2 + 1.2 * math.max(0.0, toward))) * r;
    _c.save();
    _c.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r * 1.07)));
    _c.drawCircle(
      hc,
      r * 1.04,
      Paint()
        ..shader = ui.Gradient.radial(
          hc + _light * (r * 0.5),
          r * 1.2,
          [Color.lerp(hair, Colors.white, 0.28)!, hair, Color.lerp(hair, Colors.black, 0.3)!],
          const [0, 0.5, 1],
        ),
    );
    _c.restore();
    if (toward < -0.35) return;
    // twarz: oczy, nos, usta
    for (final sg in [-1.0, 1.0]) {
      final (e, ze, _) = at(0.088, 0.036 * sg, 0.018);
      if (ze > zc + 0.015) {
        _c.save();
        _c.translate(e.dx, e.dy);
        _c.scale(1, 1.25);
        _c.drawCircle(Offset.zero, math.max(1.1, r * 0.085), Paint()..color = eye);
        _c.restore();
      }
    }
    final (nose, zn, _) = at(0.104, 0, -0.012);
    if (zn > zc + 0.01) {
      _c.drawCircle(nose, r * (0.15 - 0.07 * math.max(0.0, toward)),
          Paint()..color = Color.lerp(_tint(skin, zc), Colors.black, 0.07)!);
    }
    final (m0, zm, _) = at(0.088, -0.022, -0.05);
    final (m1, _, _) = at(0.088, 0.022, -0.05);
    if (zm > zc + 0.03) {
      _c.drawLine(
          m0,
          m1,
          Paint()
            ..color = const Color(0xCC8C4D40)
            ..strokeWidth = math.max(1.0, r * 0.063)
            ..strokeCap = StrokeCap.round);
    }
  }

  void _shoe(V3 an, V3 to, double z, V3 front) {
    final d = (to - an).unit;
    final heel = an - d * 0.045, tip = to + d * 0.02;
    const down = V3(0, 0.016, 0);
    final so = _seg(heel + down, tip + down, _sole, front, sole, z);
    final body = _seg(heel + const V3(0, -0.008, 0), tip, _shoeProf, front, shoe, z);
    _outline([so.path, body.path]);
    _paintSeg(so);
    _paintSeg(body);
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
      final ha = q['ha$sd']! + (q['ha$sd']! - q['el$sd']!).unit * 0.05;
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
    // cień ciała: rzut sylwetki na podłogę (światło z góry), rozmyty; mocniejszy w punktach styku
    final shadowPts = <Offset>[
      for (final v in q.values) _pr(V3(v.x, 0, v.z - math.max(0.0, -v.y) * 0.15)).$1,
    ];
    final hullPath = Path()..addPolygon(_hull(shadowPts), true);
    final dark = C.light ? 0.13 : 0.24;
    _c.drawPath(
        hullPath,
        Paint()
          ..color = Colors.black.withValues(alpha: dark)
          ..style = PaintingStyle.fill
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(2.0, 0.05 * _s)));
    final contact = Paint()..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(1.5, 0.02 * _s));
    q.forEach((key, v) {
      if (-v.y >= 0.1) return;
      if (!(key.startsWith('an') || key.startsWith('to') || key.startsWith('ha') || key.startsWith('kn') ||
          key == 'hip' || key == 'neck' || key == 'head' || key.startsWith('el'))) {
        return;
      }
      final (c, _, k) = _pr(V3(v.x, 0, v.z));
      _c.save();
      _c.translate(c.dx, c.dy);
      _c.scale(1, 0.35);
      _c.drawCircle(Offset.zero, 0.07 * _s * k,
          contact..color = Colors.black.withValues(alpha: (C.light ? 0.16 : 0.28) * (1 + v.y * 8).clamp(0.0, 1.0)));
      _c.restore();
    });
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
    final items = <_Item>[];
    final facing = q['head']!.x - q['hip']!.x;
    for (final sd in ['N', 'F']) {
      final sh = q['sh$sd']!, el = q['el$sd']!, ha = q['ha$sd']!;
      final hp = q['hp$sd']!, kn = q['kn$sd']!, an = q['an$sd']!, to = q['to$sd']!;
      final fA = _anterior((el - sh).unit), fF = _anterior((ha - el).unit);
      final fT = _anterior((kn - hp).unit), fS = _anterior((an - kn).unit);
      final zL = zof([hp, kn, an]), zA = zof([sh, el, ha]), zFt = zof([an, to]);
      // udo i goleń / ramię i przedramię na wyraźnie różnej głębokości → osobno w kolejce malowania
      final zT = zof([hp, kn]), zS = zof([kn, an, to]);
      if ((zT - zS).abs() < 0.05) {
        items.add(_Item(zL, [(hp, kn, 0.07), (kn, an, 0.05), (an, to, 0.04)], () => _leg(hp, kn, an, to, fT, fS, zL, zFt)));
      } else {
        items
          ..add(_Item(zT, [(hp, kn, 0.07)], () => _thighOnly(hp, kn, an, fT, zT)))
          ..add(_Item(zS, [(kn, an, 0.05), (an, to, 0.04)], () => _shinOnly(hp, kn, an, to, fT, fS, zS, zFt)));
      }
      final zU = zof([sh, el]), zF = zof([el, ha]);
      if ((zU - zF).abs() < 0.05) {
        items.add(_Item(zA + 0.004, [(sh, el, 0.045), (el, ha, 0.04)], () => _arm(sh, el, ha, fA, fF, zA, facing)));
      } else {
        items
          ..add(_Item(zU + 0.004, [(sh, el, 0.045)], () => _upperArmOnly(sh, el, fA, zU)))
          ..add(_Item(zF + 0.004, [(el, ha, 0.04)], () => _forearmOnly(el, ha, fF, zF, facing)));
      }
    }
    // tułów w dwóch częściach (miednica, klatka) – przy pochylonym ciele i obróconej kamerze każda ma inną głębokość
    final secs = _secs();
    (double, double, double, double) at(double t) => _secAt(secs, t);
    final hipV = q['hip']!, neckV = q['neck']!;
    final zt = zof([hipV, neckV]);
    final midV = V3.lerp(hipV, neckV, 0.35);
    final zP = zof([hipV, V3.lerp(hipV, neckV, 0.3)]), zC = zof([V3.lerp(hipV, neckV, 0.4), neckV]);
    if ((zP - zC).abs() < 0.05) {
      items.add(_Item(zt, [(hipV, neckV, 0.13)], () => _torsoDraw(q, zt), torso: true));
    } else {
      items
        ..add(_Item(zP, [(hipV, midV, 0.13)], () => _pelvisDraw(q, zt, secs, at), torso: true))
        ..add(_Item(zC, [(midV, neckV, 0.13)], () => _chestDraw(q, zt, secs, at), torso: true));
    }
    final headV = q['head']!;
    items.add(_Item(zof([headV]) + 0.002, [(headV, headV, 0.1)], () => _head(q)));
    items.add(_Item(zof([q['haN']!]) + 0.01, const [], () => _holds(q)));
    for (final it in _order(items)) {
      it.draw();
    }
  }

  /// Kolejność malowania: gdy dwie części nakładają się na ekranie, z tyłu idzie ta, która w miejscu
  /// nałożenia jest dalej od widza (a nie ta o mniejszej średniej głębokości – przy wyciągniętej ręce,
  /// pochylonym tułowiu czy obróconej kamerze średnia myliła i ręce znikały za ciałem albo
  /// prześwitywały przez nie). Bez nałożenia lub przy cyklu – według średniej głębokości.
  List<_Item> _order(List<_Item> items) {
    // rzut kapsuł na ekran: (a, b, za, zb, promień)
    final caps = [
      for (final it in items)
        [
          for (final (a, b, r) in it.caps)
            () {
              final (pa, za, ka) = cam.project(a);
              final (pb, zb, _) = cam.project(b);
              return (pa, pb, za, zb, r * ka);
            }(),
        ],
    ];
    final n = items.length;
    final behind = List.generate(n, (_) => <int>{}); // behind[i] – kto musi być narysowany przed i
    for (var i = 0; i < n; i++) {
      for (var k = i + 1; k < n; k++) {
        double? best; // najmniejszy „zapas” odległości (ujemny = nakładają się)
        double zi = 0, zk = 0;
        for (final ci in caps[i]) {
          for (final ck in caps[k]) {
            final (d, s, t) = _segDist(ci.$1, ci.$2, ck.$1, ck.$2);
            final gap = d - (ci.$5 + ck.$5) * 0.85;
            if (gap < 0 && (best == null || gap < best)) {
              best = gap;
              zi = ci.$3 + (ci.$4 - ci.$3) * s;
              zk = ck.$3 + (ck.$4 - ck.$3) * t;
            }
          }
        }
        if (best == null) continue;
        if ((zi - zk).abs() < 0.04) continue; // prawie ta sama głębokość – zostaje kolejność wg średniej
        if (zi < zk) {
          behind[k].add(i);
        } else {
          behind[i].add(k);
        }
      }
    }
    final done = List.filled(n, false);
    final out = <_Item>[];
    while (out.length < n) {
      int? pick;
      for (var i = 0; i < n; i++) {
        if (done[i] || behind[i].any((j) => !done[j])) continue;
        if (pick == null || items[i].z < items[pick].z) pick = i;
      }
      if (pick == null) {
        // cykl – najdalszy z pozostałych
        for (var i = 0; i < n; i++) {
          if (!done[i] && (pick == null || items[i].z < items[pick].z)) pick = i;
        }
      }
      done[pick!] = true;
      out.add(items[pick]);
    }
    return out;
  }

  /// Najmniejsza odległość odcinków ab i cd na ekranie i parametry najbliższych punktów (0…1).
  static (double, double, double) _segDist(Offset a, Offset b, Offset c, Offset d) {
    final u = b - a, v = d - c, w = a - c;
    final aa = u.dx * u.dx + u.dy * u.dy, bb = u.dx * v.dx + u.dy * v.dy, cc = v.dx * v.dx + v.dy * v.dy;
    final dd = u.dx * w.dx + u.dy * w.dy, ee = v.dx * w.dx + v.dy * w.dy;
    final den = aa * cc - bb * bb;
    double s, t;
    if (aa < 1e-9 && cc < 1e-9) {
      s = 0;
      t = 0;
    } else if (aa < 1e-9) {
      s = 0;
      t = (ee / cc).clamp(0.0, 1.0);
    } else if (cc < 1e-9) {
      t = 0;
      s = (-dd / aa).clamp(0.0, 1.0);
    } else {
      s = den.abs() < 1e-9 ? 0.0 : ((bb * ee - cc * dd) / den).clamp(0.0, 1.0);
      t = ((bb * s + ee) / cc);
      if (t < 0) {
        t = 0;
        s = (-dd / aa).clamp(0.0, 1.0);
      } else if (t > 1) {
        t = 1;
        s = ((bb - dd) / aa).clamp(0.0, 1.0);
      }
    }
    final p = a + u * s, q2 = c + v * t;
    return ((p - q2).distance, s, t);
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
