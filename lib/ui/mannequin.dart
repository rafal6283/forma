import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/figure.dart';

/// Realistyczna postać rysowana na szkielecie [Joints]: kończyny zwężające się jak mięśnie,
/// sylwetka tułowia, głowa z włosami, dłonie, stopy w butach, ubranie i światłocień.
/// Kształty są te same co w tool/mannequin.py (tam je projektujemy na podglądzie).
class Mannequin {
  // promienie (m): przy stawie bliższym tułowia / dalszym
  static const armUp = (0.056, 0.042), armLo = (0.042, 0.030);
  static const legUp = (0.086, 0.058), legLo = (0.060, 0.036);
  static const neckR = 0.038, headRx = 0.092, headRy = 0.108, handR = 0.040;

  /// Widok z boku: (pozycja wzdłuż biodro→szyja, przód, tył).
  static const sideTorso = [
    (-0.06, 0.090, 0.110),
    (0.15, 0.085, 0.095),
    (0.45, 0.085, 0.075),
    (0.72, 0.125, 0.085),
    (0.90, 0.110, 0.080),
    (1.00, 0.055, 0.050),
  ];

  /// Widok z przodu: (pozycja, połowa szerokości).
  static const frontTorso = [
    (-0.06, 0.150),
    (0.12, 0.140),
    (0.45, 0.115),
    (0.75, 0.150),
    (0.92, 0.175),
    (1.00, 0.080),
  ];

  static const skin = Color(0xFFE8BE9C), skinFar = Color(0xFFB28668);
  static const shirt = Color(0xFFFF6A3D), shirtFar = Color(0xFFBA4828);
  static const shorts = Color(0xFF343A4E), shortsFar = Color(0xFF242836);
  static const shoe = Color(0xFFF0F2F6), shoeFar = Color(0xFFA0A6B2);
  static const hair = Color(0xFF3A2A20), eye = Color(0xFF281E1A);

  /// Kierunek światła (z lewej, z góry) w układzie ekranu.
  static const _light = Offset(-0.45, -0.89);

  final Canvas c;
  final Joints j;
  final Offset Function(Offset) P;
  final double s;

  /// Oddech w pozycjach statycznych: -1…1.
  final double breath;

  Mannequin(this.c, this.j, this.P, this.s, {this.breath = 0});

  static Offset _dir(double a) {
    final r = a * math.pi / 180;
    return Offset(math.sin(r), math.cos(r));
  }

  static Offset _unit(Offset v) {
    final l = v.distance;
    return l == 0 ? const Offset(0, -1) : v / l;
  }

  static Offset _perp(Offset v) => Offset(-v.dy, v.dx);

  /// Kierunek „twarzy” (przód ciała) dla odcinka nachylonego pod kątem [a].
  Offset _face(double a) {
    final d = _dir(a);
    final f = Offset(-d.dy, d.dx);
    return j.back ? -f : f;
  }

  static Color _lit(Color c) => Color.lerp(c, Colors.white, 0.13)!;
  static Color _dark(Color c) => Color.lerp(c, Colors.black, 0.24)!;

  /// Gradient w poprzek kształtu: jaśniej od strony światła.
  Paint _shade(Color base, Offset a, Offset b, double r) {
    final u = _unit(b - a);
    var n = _perp(u);
    if (n.dx * _light.dx + n.dy * _light.dy < 0) n = -n;
    final m = (a + b) / 2;
    return Paint()
      ..isAntiAlias = true
      ..shader = ui.Gradient.linear(m + n * r, m - n * r, [_lit(base), base, _dark(base)], const [0, 0.42, 1]);
  }

  /// Zwężająca się kapsuła a→b (współrzędne modelu), promienie w metrach.
  Path _capsule(Offset a, Offset b, double ra, double rb) {
    final pa = P(a), pb = P(b);
    final u = _unit(pb - pa);
    final n = _perp(u);
    final path = Path();
    const steps = 8;
    for (var i = 0; i <= steps; i++) {
      final ang = math.pi / 2 + math.pi * i / steps;
      final p = pa + (u * math.cos(ang) + n * math.sin(ang)) * (ra * s);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    for (var i = 0; i <= steps; i++) {
      final ang = -math.pi / 2 + math.pi * i / steps;
      final p = pb + (u * math.cos(ang) + n * math.sin(ang)) * (rb * s);
      path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  /// Gładka zamknięta krzywa przez punkty (ekranowe).
  static Path _smooth(List<Offset> pts) {
    final path = Path();
    final n = pts.length;
    Offset mid(int i) => (pts[i % n] + pts[(i + 1) % n]) / 2;
    final m0 = mid(0);
    path.moveTo(m0.dx, m0.dy);
    for (var i = 1; i <= n; i++) {
      final p = pts[i % n], m = mid(i);
      path.quadraticBezierTo(p.dx, p.dy, m.dx, m.dy);
    }
    return path..close();
  }

  final _edge = Paint()
    ..style = PaintingStyle.stroke
    ..color = const Color(0x40000000)
    ..strokeWidth = 1;

  void _limbPart(Color col, Color far, bool isFar, Offset a, Offset b, double ra, double rb, {bool edge = true}) {
    final path = _capsule(a, b, ra, rb);
    c.drawPath(path, _shade(isFar ? far : col, P(a), P(b), math.max(ra, rb) * s));
    if (edge && !isFar) c.drawPath(path, _edge);
  }

  void _arm(String side, bool far) {
    final sh = j['sh$side'], el = j['el$side'], ha = j['ha$side'];
    _limbPart(skin, skinFar, far, el, ha, armLo.$1, armLo.$2);
    _limbPart(skin, skinFar, far, sh, el, armUp.$1, armUp.$2);
    // rękaw koszulki
    final mid = Offset.lerp(sh, el, 0.38)!;
    _limbPart(shirt, shirtFar, far, sh, mid, armUp.$1 + 0.005, armUp.$1 - 0.002);
    // dłoń
    final u = _unit(ha - el);
    final hc = P(ha + u * 0.03);
    c.drawCircle(hc, handR * s, Paint()..color = far ? skinFar : skin);
    if (!far) c.drawCircle(hc, handR * s, _edge);
  }

  void _leg(String side, bool far) {
    final hp = j['hp$side'], kn = j['kn$side'], an = j['an$side'];
    _limbPart(skin, skinFar, far, kn, an, legLo.$1, legLo.$2);
    _limbPart(skin, skinFar, far, hp, kn, legUp.$1, legUp.$2);
    // nogawka spodenek
    final mid = Offset.lerp(hp, kn, 0.45)!;
    _limbPart(shorts, shortsFar, far, hp, mid, legUp.$1 + 0.006, (legUp.$1 + legUp.$2) / 2 + 0.006);
    _foot(side, far);
  }

  void _foot(String side, bool far) {
    final an = j['an$side'], to = j['to$side'], kn = j['kn$side'];
    final col = far ? shoeFar : shoe;
    if (j.front) {
      // but widziany od przodu: owal w poprzek goleni, tuż pod kostką
      // stopa na ziemi (goleń w dół) leży płasko; uniesiona — w poprzek goleni
      final sd = _unit(an - kn);
      final u = sd.dy > 0.6 ? const Offset(1, 0) : _perp(sd);
      final v = _perp(u);
      final ctr = Offset.lerp(an, to, 0.4)!;
      final pts = [
        for (var i = 0; i < 20; i++)
          P(ctr + u * (0.058 * math.cos(2 * math.pi * i / 20)) + v * (0.034 * math.sin(2 * math.pi * i / 20))),
      ];
      final path = Path()..addPolygon(pts, true);
      c.drawPath(path, Paint()..color = col);
      if (!far) c.drawPath(path, _edge);
      return;
    }
    // n = strona grzbietu stopy (podeszwa po przeciwnej), niezależnie od kąta stopy
    final sv = to - an;
    final u = _unit(sv);
    final n = j.back ? _perp(u) : -_perp(u);
    const shape = [(-0.35, -0.04), (-0.45, 0.01), (-0.2, 0.05), (0.6, 0.035), (1.25, 0.0), (1.1, -0.04), (0.0, -0.045)];
    final pts = [for (final (ks, kn) in shape) P(an + sv * ks + n * kn)];
    final path = _smooth(pts);
    c.drawPath(path, Paint()..color = col);
    // podeszwa
    c.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, s * 0.008)
        ..color = Color.lerp(col, Colors.black, 0.35)!,
    );
  }

  void _torso() {
    final hip = j['hip'], neck = j['neck'];
    final d = neck - hip;
    final len = d.distance;
    final u = _unit(d);
    final chest = 1 + 0.03 * breath;
    final pts = <Offset>[];
    if (j.front) {
      final n = _perp(u);
      for (final (t, w) in frontTorso) {
        pts.add(P(hip + u * (len * t) + n * (w * (t > 0.5 ? chest : 1))));
      }
      for (final (t, w) in frontTorso.reversed) {
        pts.add(P(hip + u * (len * t) - n * (w * (t > 0.5 ? chest : 1))));
      }
    } else {
      final f = _face(_angle(u));
      for (final (t, fr, _) in sideTorso) {
        pts.add(P(hip + u * (len * t) + f * (fr * (t > 0.5 ? chest : 1))));
      }
      for (final (t, _, bk) in sideTorso.reversed) {
        pts.add(P(hip + u * (len * t) - f * bk));
      }
    }
    final path = _smooth(pts);
    c.drawPath(path, _shade(shirt, P(hip), P(neck), 0.15 * s));
    c.drawPath(path, _edge);
    _shorts(hip, u, len);
  }

  /// Kąt (jak w Pose) odcinka o kierunku [u].
  static double _angle(Offset u) => math.atan2(u.dx, u.dy) * 180 / math.pi;

  void _shorts(Offset hip, Offset u, double len) {
    final List<Offset> pts;
    if (j.front) {
      final n = _perp(u);
      pts = [
        hip + u * (len * 0.18) + n * 0.145,
        hip + u * (len * 0.18) - n * 0.145,
        hip - u * (len * 0.08) - n * 0.15,
        hip - u * (len * 0.08) + n * 0.15,
      ];
    } else {
      final f = _face(_angle(u));
      pts = [
        hip + u * (len * 0.2) + f * 0.088,
        hip - u * 0.07 + f * 0.095,
        hip - u * 0.07 - f * 0.115,
        hip + u * (len * 0.2) - f * 0.1,
      ];
    }
    final sp = pts.map(P).toList();
    final path = Path()..addPolygon(sp, true);
    c.drawPath(path, _shade(shorts, P(hip - u * 0.07), P(hip + u * (len * 0.2)), 0.12 * s));
    // gumka w pasie
    c.drawLine(
      sp[0],
      sp[3],
      Paint()
        ..color = Color.lerp(shorts, Colors.white, 0.18)!
        ..strokeWidth = math.max(1.0, s * 0.012),
    );
  }

  void _neckAndHead() {
    final neck = j['neck'], head = j['head'];
    _limbPart(skin, skinFar, false, neck, Offset.lerp(neck, head, 0.55)!, neckR, neckR, edge: false);
    final up = _dir(j.headDir);
    final f = j.front ? _perp(up) : _face(j.headDir);
    final hc = P(head);
    final rx = headRx * s, ry = headRy * s;
    final outline = <Offset>[];
    final hairPts = <Offset>[];
    for (var i = 0; i < 48; i++) {
      final th = 2 * math.pi * i / 48;
      final p = hc + up * (ry * math.sin(th)) + f * (rx * math.cos(th));
      outline.add(p);
      // włosy: czubek i tył głowy; z przodu tylko „czapeczka” u góry
      final keep = j.front ? math.sin(th) > 0.25 : math.sin(th) - 0.75 * math.cos(th) > -0.2;
      if (keep) hairPts.add(hc + (p - hc) * 1.04);
    }
    // nos (widok z boku) — mała wypukłość z przodu twarzy
    if (!j.front) {
      c.drawCircle(hc + f * (rx * 0.98) - up * (ry * 0.1), s * 0.024, Paint()..color = skin);
    }
    final headPath = Path()..addPolygon(outline, true);
    c.drawPath(headPath, _shade(skin, hc - up * ry, hc + up * ry, rx));
    if (hairPts.length > 2) {
      // próbkowanie startuje od kierunku twarzy (bez włosów), więc łuk jest ciągły
      c.drawPath(Path()..addPolygon(hairPts, true), Paint()..color = hair);
    }
    if (!j.front) {
      c.drawCircle(hc + f * (rx * 0.6) + up * (ry * 0.1), math.max(1.2, s * 0.012), Paint()..color = eye);
    }
  }

  /// Cień na podłodze pod postacią.
  void floorShadow() {
    double lo = double.infinity, hi = -double.infinity;
    for (final v in j.p.values) {
      lo = math.min(lo, v.dx);
      hi = math.max(hi, v.dx);
    }
    // im wyżej ciało, tym słabszy cień
    final lowest = j.p.values.map((v) => v.dy).reduce(math.max);
    final fade = (1 - (-lowest).clamp(0.0, 0.5) * 1.4).clamp(0.2, 1.0);
    final cx = (lo + hi) / 2, w = (hi - lo) / 2 + 0.18;
    final r = w * s, flat = 0.035 / w;
    c.save();
    c.translate(P(Offset(cx, 0)).dx, P(Offset(cx, 0)).dy);
    c.scale(1, flat);
    c.drawCircle(
      Offset.zero,
      r,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset.zero,
          r,
          [Colors.black.withValues(alpha: 0.45 * fade), Colors.black.withValues(alpha: 0.18 * fade), Colors.black.withValues(alpha: 0)],
          const [0, 0.6, 1],
        ),
    );
    c.restore();
  }

  /// Cała postać w kolejności od najdalszych elementów.
  void paint() {
    if (j.front) {
      _leg('F', false);
      _leg('N', false);
      _torso();
      _neckAndHead();
      _arm('F', false);
      _arm('N', false);
    } else {
      _arm('F', true);
      _leg('F', true);
      _torso();
      _neckAndHead();
      _leg('N', false);
      _arm('N', false);
    }
  }
}
