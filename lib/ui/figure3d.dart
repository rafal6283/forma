import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/figure.dart';
import 'mannequin.dart';
import 'technique.dart';
import 'theme.dart';

/// Punkt w przestrzeni: x w prawo, y w dół (podłoga y = 0), z do widza (w widoku z boku).
class V3 {
  final double x, y, z;
  const V3(this.x, this.y, this.z);
  V3 operator +(V3 o) => V3(x + o.x, y + o.y, z + o.z);
  V3 operator -(V3 o) => V3(x - o.x, y - o.y, z - o.z);
  V3 operator *(double k) => V3(x * k, y * k, z * k);
  double get length => math.sqrt(x * x + y * y + z * z);
  V3 get unit {
    final l = length;
    return l == 0 ? const V3(0, -1, 0) : this * (1 / l);
  }

  V3 cross(V3 o) => V3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  static V3 lerp(V3 a, V3 b, double t) => a + (b - a) * t;
}

/// Stawy 2D → 3D. Pozy z boku: kończyny bliższe/dalsze rozsunięte na szerokość barków i bioder.
/// Pozy z przodu: płaszczyzna czołowa, palce stóp do widza.
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

class _Part {
  final V3 a, b;
  final double ra, rb;
  final Color color;
  final String? tag;
  final double bias; // pierwszeństwo przy równej głębi (rękaw na ramieniu itp.)
  final bool sphere, shadow, edge;
  _Part(this.a, this.b, this.ra, this.rb, this.color, {this.tag, this.bias = 0, this.shadow = true, this.edge = true})
      : sphere = false;
  _Part.ball(this.a, this.ra, this.color, {this.tag, this.bias = 0})
      : b = a,
        rb = ra,
        sphere = true,
        shadow = true,
        edge = true;
}

/// Rekwizyty sceny w układzie 3D.
class Prop3 {
  final String type; // chair / wall / bar
  final Rect rect; // jak w widoku 2D
  const Prop3(this.type, this.rect);
}

/// Malarz postaci 3D: części ciała jako bryły (kapsuły i kule) sortowane po głębi, cieniowane,
/// z cieniem na podłodze; obrót kamery gestem.
class Figure3DPainter extends CustomPainter {
  final Joints j;
  final Cam cam;
  final Rect bounds; // kadr w układzie obrazu kamery (metry)
  final bool floor, hands;
  final String? hold;
  final List<Prop3> props;
  final double breath;
  final Map<String, double> glow;
  final (Offset, Offset, double)? arrow; // staw teraz → cel (2D modelu), siła

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
    this.arrow,
  });

  static const _light = Offset(-0.45, -0.89);

  late double _s;
  late Offset _o;

  Offset _scr(Offset p) => p * _s + _o;

  (Offset, double, double) _pr(V3 p) {
    final (o, z, k) = cam.project(p);
    return (_scr(o), z, k);
  }

  List<_Part> _body(Map<String, V3> q) {
    final parts = <_Part>[];
    const m = Mannequin.skin, sh = Mannequin.shirt, sr = Mannequin.shorts, shoe = Mannequin.shoe;
    final hip = q['hip']!, neck = q['neck']!, head = q['head']!;
    V3 spine(double t) => V3.lerp(hip, neck, t);
    final chest = 1 + 0.03 * breath;

    // tułów: miednica, brzuch, klatka, barki
    parts.add(_Part(q['hpN']!, q['hpF']!, 0.105, 0.105, sr, tag: 'pelvis', edge: false));
    parts.add(_Part(hip, spine(0.22), 0.108, 0.104, sr, tag: 'pelvis', bias: 0.002, edge: false));
    parts.add(_Part(spine(0.18), spine(0.5), 0.1, 0.098, sh, tag: 'abs', edge: false));
    parts.add(_Part(spine(0.48), spine(0.82), 0.104, 0.118 * chest, sh, tag: 'chest', edge: false));
    final shN = q['shN']!, shF = q['shF']!;
    final c1 = spine(0.86) + (shN - neck) * 0.62, c2 = spine(0.86) + (shF - neck) * 0.62;
    parts.add(_Part(c1, c2, 0.085 * chest, 0.085 * chest, sh, tag: 'chest', bias: 0.001, edge: false));
    parts.add(_Part(spine(0.8), neck, 0.11, 0.075, sh, tag: 'chest', edge: false));
    // szyja i głowa (głowa rysowana osobno — włosy, oczy)
    parts.add(_Part(neck, V3.lerp(neck, head, 0.55), 0.042, 0.04, m, bias: -0.002));

    for (final sd in ['N', 'F']) {
      final s0 = q['sh$sd']!, el = q['el$sd']!, ha = q['ha$sd']!;
      final hp = q['hp$sd']!, kn = q['kn$sd']!, an = q['an$sd']!, to = q['to$sd']!;
      // ręka
      parts.add(_Part.ball(s0, 0.062, sh, tag: 'shoulder', bias: 0.004));
      parts.add(_Part(s0, el, Mannequin.armUp.$1, Mannequin.armUp.$2, m, tag: 'upperArm'));
      parts.add(_Part(s0, V3.lerp(s0, el, 0.38), 0.062, 0.052, sh, tag: 'shoulder', bias: 0.003));
      parts.add(_Part(el, ha, Mannequin.armLo.$1, Mannequin.armLo.$2, m, tag: 'forearm'));
      parts.add(_Part.ball(ha + (ha - el).unit * 0.03, Mannequin.handR, m, bias: 0.002));
      // noga
      parts.add(_Part(hp, kn, Mannequin.legUp.$1, Mannequin.legUp.$2, m, tag: 'thigh'));
      parts.add(_Part(hp, V3.lerp(hp, kn, 0.45), 0.092, 0.08, sr, tag: 'thigh', bias: 0.003));
      parts.add(_Part(kn, an, Mannequin.legLo.$1, Mannequin.legLo.$2, m, tag: 'shin'));
      // but: od pięty do palców
      final fd = (to - an).unit;
      parts.add(_Part(an - fd * 0.035, to + fd * 0.01, 0.046, 0.036, shoe, bias: 0.002));
    }

    // sprzęt w dłoniach
    final lat = j.front ? const V3(1, 0, 0) : const V3(0, 0, 1);
    const metal = Color(0xFF4A5262), dark = Color(0xFF2B3040);
    final hh = hold;
    if (hh != null && hh != 'band') {
      final single = hh == 'kb' || hh == 'db1';
      for (final sd in single ? ['N'] : ['N', 'F']) {
        final ha = q['ha$sd']!;
        if (hh == 'kb') {
          parts.add(_Part.ball(ha + const V3(0, 0.1, 0), 0.075, dark, bias: 0.01));
          parts.add(_Part(ha - lat * 0.04, ha + lat * 0.04, 0.016, 0.016, metal, bias: 0.011));
        } else {
          parts.add(_Part(ha - lat * 0.09, ha + lat * 0.09, 0.016, 0.016, metal, bias: 0.01));
          parts.add(_Part(ha - lat * 0.1, ha - lat * 0.06, 0.045, 0.045, dark, bias: 0.011));
          parts.add(_Part(ha + lat * 0.06, ha + lat * 0.1, 0.045, 0.045, dark, bias: 0.011));
        }
      }
    }
    if (hh == 'band') parts.add(_Part(q['haN']!, q['haF']!, 0.01, 0.01, C.accent, bias: 0.02, shadow: false));
    return parts;
  }

  Path _capsule(Offset pa, Offset pb, double ra, double rb) {
    var u = pb - pa;
    final l = u.distance;
    u = l == 0 ? const Offset(0, -1) : u / l;
    final n = Offset(-u.dy, u.dx);
    final path = Path();
    const steps = 8;
    for (var i = 0; i <= steps; i++) {
      final ang = math.pi / 2 + math.pi * i / steps;
      final p = pa + (u * math.cos(ang) + n * math.sin(ang)) * ra;
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    for (var i = 0; i <= steps; i++) {
      final ang = -math.pi / 2 + math.pi * i / steps;
      final p = pb + (u * math.cos(ang) + n * math.sin(ang)) * rb;
      path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  Color _depthTint(Color c, double z) {
    // dalej od widza = ciemniej (głębia), bliżej = pełny kolor
    final t = ((0.35 - z) / 0.7).clamp(0.0, 1.0);
    return Color.lerp(c, Colors.black, 0.28 * t)!;
  }

  Paint _shade(Color base, Offset a, Offset b, double r) {
    var u = b - a;
    u = u.distance == 0 ? const Offset(0, -1) : u / u.distance;
    var n = Offset(-u.dy, u.dx);
    if (n.dx * _light.dx + n.dy * _light.dy < 0) n = -n;
    final m = (a + b) / 2;
    return Paint()
      ..shader = ui.Gradient.linear(
        m + n * r,
        m - n * r,
        [Color.lerp(base, Colors.white, 0.16)!, base, Color.lerp(base, Colors.black, 0.3)!],
        const [0, 0.4, 1],
      );
  }

  Paint _ballShade(Color base, Offset c, double r) => Paint()
    ..shader = ui.Gradient.radial(
      c + _light * (r * 0.45),
      r * 1.5,
      [Color.lerp(base, Colors.white, 0.2)!, base, Color.lerp(base, Colors.black, 0.32)!],
      const [0, 0.45, 1],
    );

  @override
  void paint(Canvas canvas, Size size) {
    _s = math.min(size.width / bounds.width, size.height / bounds.height);
    _o = Offset((size.width - bounds.width * _s) / 2 - bounds.left * _s, (size.height - bounds.height * _s) / 2 - bounds.top * _s);
    final q = lift3d(j);
    final parts = _body(q);

    // --- podłoga: dysk w perspektywie i cienie części ciała
    if (floor && !hands) {
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
      canvas.save();
      canvas.clipPath(disk);
      canvas.translate(b.center.dx, b.center.dy);
      canvas.scale(1, b.height / b.width);
      canvas.drawCircle(
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
      canvas.restore();
      // cienie: rzut części na podłogę (światło z góry)
      final sh = Paint()
        ..color = Colors.black.withValues(alpha: C.light ? 0.13 : 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
      for (final p in parts.where((p) => p.shadow)) {
        final (a, _, ka) = _pr(V3(p.a.x, 0, p.a.z));
        final (bb, _, kb) = _pr(V3(p.b.x, 0, p.b.z));
        final lift = (-(p.a.y + p.b.y) / 2).clamp(0.0, 2.0);
        final fade = (1 - lift * 0.35).clamp(0.25, 1.0);
        canvas.drawPath(
          _capsule(a, bb, p.ra * _s * ka, p.rb * _s * kb),
          sh..color = Colors.black.withValues(alpha: (C.light ? 0.1 : 0.24) * fade),
        );
      }
    }

    // --- rekwizyty za postacią (ściana) i pozostałe
    final metal = Paint()..color = C.prop;
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
          canvas.drawPath(Path()..addPolygon(pts, true), Paint()..color = C.surface2.withValues(alpha: 0.85));
        case 'chair':
          const d = 0.22;
          final top = [
            V3(r.left, r.top, -d),
            V3(r.right, r.top, -d),
            V3(r.right, r.top, d),
            V3(r.left, r.top, d),
          ];
          for (final c in top) {
            final (a, _, ka) = _pr(c);
            final (b, _, _) = _pr(V3(c.x, 0, c.z));
            canvas.drawLine(a, b, Paint()
              ..color = Color.lerp(C.prop, Colors.black, 0.25)!
              ..strokeWidth = math.max(2.0, 0.03 * _s * ka));
          }
          final seat = top.map((v) => _pr(v).$1).toList();
          canvas.drawPath(Path()..addPolygon(seat, true), metal);
          final front = [top[2], top[3], top[3] + const V3(0, 0.05, 0), top[2] + const V3(0, 0.05, 0)]
              .map((v) => _pr(v).$1)
              .toList();
          canvas.drawPath(Path()..addPolygon(front, true), Paint()..color = Color.lerp(C.prop, Colors.black, 0.3)!);
        case 'bar':
          final lat = j.front ? const V3(1, 0, 0) : const V3(0, 0, 1);
          final hc = q['haN']!;
          final c = V3(j.front ? (q['haN']!.x + q['haF']!.x) / 2 : hc.x, hc.y, j.front ? hc.z : 0);
          final (a, _, ka) = _pr(c - lat * 0.7);
          final (b, _, kb) = _pr(c + lat * 0.7);
          canvas.drawPath(_capsule(a, b, 0.022 * _s * ka, 0.022 * _s * kb), _shade(C.prop, a, b, 0.022 * _s));
      }
    }

    // --- bryły ciała od najdalszej
    final proj = <(_Part, double)>[];
    for (final p in parts) {
      final (_, za, _) = cam.project(p.a);
      final (_, zb, _) = cam.project(p.b);
      proj.add((p, (za + zb) / 2 + p.bias));
    }
    // głowa jako osobny element w kolejce
    final (_, zh, _) = cam.project(q['head']!);
    proj.add((_Part.ball(q['head']!, 0.1, Mannequin.skin, tag: '_head'), zh));
    proj.sort((a, b) => a.$2.compareTo(b.$2));

    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.black.withValues(alpha: 0.22);
    for (final (p, z) in proj) {
      if (p.tag == '_head') {
        _head(canvas, q, z);
        continue;
      }
      final (a, za, ka) = _pr(p.a);
      final col = _depthTint(p.color, za);
      if (p.sphere) {
        final r = p.ra * _s * ka;
        canvas.drawCircle(a, r, _ballShade(col, a, r));
        final g = glow[p.tag] ?? 0;
        if (g > 0.02) canvas.drawCircle(a, r, Paint()..color = glowColor(0.55 * g));
        if (p.edge) canvas.drawCircle(a, r, edge);
        continue;
      }
      final (b, _, kb) = _pr(p.b);
      final ra = p.ra * _s * ka, rb = p.rb * _s * kb;
      final path = _capsule(a, b, ra, rb);
      canvas.drawPath(path, _shade(col, a, b, math.max(ra, rb)));
      final g = glow[p.tag] ?? 0;
      if (g > 0.02) canvas.drawPath(path, Paint()..color = glowColor(0.55 * g));
      if (p.edge) canvas.drawPath(path, edge);
    }

    // --- strzałka ruchu
    final ar = arrow;
    if (ar != null) {
      final (from, to, strength) = ar;
      final a = _pr(V3(from.dx, from.dy, 0)).$1, b = _pr(V3(to.dx, to.dy, 0)).$1;
      paintArrow(canvas, a, b, strength, size.shortestSide);
    }
  }

  /// Głowa: kula + włosy (czapka po stronie potylicy) + oczy i nos, gdy twarz widać.
  void _head(Canvas canvas, Map<String, V3> q, double z) {
    final head = q['head']!;
    final up = (head - q['neck']!).unit;
    V3 face;
    if (j.front) {
      face = const V3(0, 0, 1);
    } else {
      // przód głowy: prostopadle do osi głowy w płaszczyźnie ruchu
      final f = V3(-up.y, up.x, 0);
      face = j.back ? f * -1 : f;
    }
    final (c, zc, k) = _pr(head);
    final r = 0.1 * _s * k;
    final col = _depthTint(Mannequin.skin, zc);
    final ball = Path()..addOval(Rect.fromCircle(center: c, radius: r));
    canvas.drawPath(ball, _ballShade(col, c, r));
    // włosy: koło przesunięte ku potylicy i w górę (w rzucie), przycięte do głowy.
    // Twarzą do widza → czapka u góry; tyłem → włosy zakrywają prawie całą głowę.
    Offset dir(V3 v) {
      final (p, _, _) = _pr(head + v * 0.1);
      return (p - c) / (0.1 * _s * k);
    }
    final (_, zf, _) = cam.project(head + face * 0.1);
    final toward = ((zf - zc) / 0.1).clamp(-1.0, 1.0);
    final hc = c + (dir(face * -1) * 0.6 + dir(up) * (0.15 + 0.35 * math.max(0.0, toward))) * r;
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r * 1.04)));
    canvas.drawCircle(hc, r * 1.0, Paint()..color = Mannequin.hair);
    canvas.restore();
    // nos i oczy — tylko gdy są po stronie widza
    final side = up.cross(face).unit;
    final (nose, zn, _) = _pr(head + face * 0.1 - up * 0.012);
    if (zn > zc + 0.01) canvas.drawCircle(nose, r * 0.2, Paint()..color = col);
    for (final sgn in [-1.0, 1.0]) {
      final (e, ze, _) = _pr(head + face * 0.086 + side * (0.036 * sgn) + up * 0.012);
      if (ze > zc + 0.03) canvas.drawCircle(e, math.max(1.2, r * 0.1), Paint()..color = Mannequin.eye);
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
      final rr = Rect.fromCircle(center: o, radius: 0.1 * k);
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
