import 'dart:math' as math;
import 'dart:ui' show Offset;

/// Szkielet postaci — ta sama kinematyka co tool/figure.py (tam projektujemy pozy).
///
/// Kąty w stopniach od pionu w dół, dodatnie w stronę +x (postać patrzy w prawo).
/// Oś y rośnie w dół, podłoga to y = 0.
class Body {
  static const torso = 0.50, neck = 0.07, headR = 0.10;
  static const upper = 0.30, fore = 0.28;
  static const thigh = 0.44, shin = 0.46, foot = 0.10;
  static const shoulderW = 0.17, hipW = 0.09;

  /// Promień ciała wokół stawu (przy opieraniu o podłogę); zgodny z tool/figure.py.
  static double thickness(String joint) => switch (joint.replaceAll(RegExp(r'[NF]$'), '')) {
        'head' => headR + 0.008,
        'hip' || 'hp' => 0.10,
        'neck' || 'sh' => 0.08,
        'kn' => 0.055,
        'an' => 0.045,
        'to' => 0.035,
        _ => 0.04,
      };
}

class Pose {
  final double t, h, fp, lift, x;
  final List<double> an, af, ln, lf;
  final bool front, back;

  const Pose({
    this.t = 180,
    double? h,
    this.an = const [8, 12],
    this.af = const [-8, -4],
    this.ln = const [2, 0],
    this.lf = const [-2, 0],
    this.fp = 0,
    this.lift = 0,
    this.x = 0,
    this.front = false,
    this.back = false,
  }) : h = h ?? t;

  static List<double> _l(Object? v, List<double> d) =>
      v is List ? v.map((e) => (e as num).toDouble()).toList() : d;

  factory Pose.fromJson(Map<String, dynamic> j) {
    double n(String k, double d) => (j[k] as num?)?.toDouble() ?? d;
    final t = n('t', 180);
    return Pose(
      t: t,
      h: n('h', t),
      an: _l(j['an'], const [8, 12]),
      af: _l(j['af'], const [-8, -4]),
      ln: _l(j['ln'], const [2, 0]),
      lf: _l(j['lf'], const [-2, 0]),
      fp: n('fp', 0),
      lift: n('lift', 0),
      x: n('x', 0),
      front: j['view'] == 'front',
      back: j['back'] == true,
    );
  }

  /// Druga strona ciała (bliższe ↔ dalsze kończyny; w widoku z przodu odbicie).
  Pose swapped() => Pose(
        t: front ? 360 - t : t,
        h: front ? 360 - h : h,
        an: af,
        af: an,
        ln: lf,
        lf: ln,
        fp: fp,
        lift: lift,
        x: front ? -x : x,
        front: front,
        back: back,
      );

  /// Interpolacja po najkrótszym łuku (krążenia ramion przechodzą przez 360°).
  static Pose lerp(Pose a, Pose b, double k) {
    double ang(double p, double q) {
      final d = ((q - p + 540) % 360) - 180;
      return p + d * k;
    }

    double lin(double p, double q) => p + (q - p) * k;
    List<double> l2(List<double> p, List<double> q) => [ang(p[0], q[0]), ang(p[1], q[1])];
    return Pose(
      t: ang(a.t, b.t),
      h: ang(a.h, b.h),
      an: l2(a.an, b.an),
      af: l2(a.af, b.af),
      ln: l2(a.ln, b.ln),
      lf: l2(a.lf, b.lf),
      fp: lin(a.fp, b.fp),
      lift: lin(a.lift, b.lift),
      x: lin(a.x, b.x),
      front: k < 0.5 ? a.front : b.front,
      back: k < 0.5 ? a.back : b.back,
    );
  }
}

/// Pozycje stawów; klucze jak w tool/figure.py (haN = dłoń bliższa, toF = palce dalszej stopy…).
class Joints {
  final Map<String, Offset> p;
  final bool front, back;
  final double headDir;
  Joints(this.p, this.front, this.back, this.headDir);

  Offset operator [](String k) => p[k]!;

  Joints shifted(Offset d) => Joints(p.map((k, v) => MapEntry(k, v + d)), front, back, headDir);

  static Offset _dir(double a) {
    final r = a * math.pi / 180;
    return Offset(math.sin(r), math.cos(r));
  }

  static Joints of(Pose s) {
    final hip = Offset(s.x, 0);
    final neck = hip + _dir(s.t) * Body.torso;
    final head = neck + _dir(s.h) * (Body.neck + Body.headR);
    final m = <String, Offset>{'hip': hip, 'neck': neck, 'head': head};
    final td = _dir(s.t);
    final perp = Offset(-td.dy, td.dx);
    for (final near in [true, false]) {
      final side = near ? 'N' : 'F';
      final sgn = near ? 1.0 : -1.0;
      var arm = near ? s.an : s.af;
      var leg = near ? s.ln : s.lf;
      Offset sh = neck, hp = hip;
      if (s.front) {
        sh = neck + perp * (Body.shoulderW * sgn);
        hp = hip + perp * (Body.hipW * sgn);
        if (!near) {
          arm = [-arm[0], -arm[1]];
          leg = [-leg[0], -leg[1]];
        }
      }
      final el = sh + _dir(arm[0]) * Body.upper;
      final ha = el + _dir(arm[1]) * Body.fore;
      final kn = hp + _dir(leg[0]) * Body.thigh;
      final an = kn + _dir(leg[1]) * Body.shin;
      final Offset toe;
      if (s.front) {
        // but od przodu: przedłużenie goleni (pod kostką, gdy stoi), lekko na zewnątrz
        toe = an + _dir(leg[1]) * 0.045 + perp * (sgn * 0.02);
      } else {
        // palcami do przodu ciała; na plecach postać jest lustrzana. fp > 0 = wspięcie na palce.
        toe = an + _dir(s.back ? leg[1] - 90 + s.fp : leg[1] + 90 - s.fp) * Body.foot;
      }
      m.addAll({'sh$side': sh, 'el$side': el, 'ha$side': ha, 'hp$side': hp, 'kn$side': kn, 'an$side': an, 'to$side': toe});
    }
    return Joints(m, s.front, s.back, s.h);
  }

  /// Najniższy punkt na podłodze (lub dłonie na drążku), potem uniesienie o lift.
  static Joints grounded(Pose s, {bool hands = false, double barY = -2.3}) {
    final j = of(s);
    double dy;
    if (hands) {
      dy = barY - j['haN'].dy;
    } else {
      // uwzględniamy grubość ciała (postać ma objętość), żeby nie „wchodziła” w podłogę
      var low = -double.infinity;
      j.p.forEach((k, v) {
        final y = v.dy + Body.thickness(k);
        if (y > low) low = y;
      });
      dy = -low - s.lift;
    }
    return j.shifted(Offset(0, dy));
  }
}

/// Animacja ćwiczenia: klatki kluczowe w pętli, płynne przejścia.
class FigAnim {
  final List<Pose> keys;
  final double cycle;
  final bool hands;
  final List<Map<String, dynamic>> props;

  FigAnim(this.keys, this.cycle, {this.hands = false, this.props = const []});

  factory FigAnim.fromJson(Map<String, dynamic> j, Map<String, Pose> lib) {
    final keys = <Pose>[];
    for (final k in j['k'] as List) {
      if (k is Map) {
        keys.add(Pose.fromJson(k.cast<String, dynamic>()));
      } else {
        final s = k as String;
        final base = lib[s.replaceAll('~', '')] ?? const Pose();
        keys.add(s.endsWith('~') ? base.swapped() : base);
      }
    }
    return FigAnim(
      keys,
      (j['s'] as num?)?.toDouble() ?? 2.0,
      hands: j['anchor'] == 'hands',
      props: ((j['props'] as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList(),
    );
  }

  /// Poza w chwili [seconds] (pętla); na każdą klatkę przypada równa część cyklu.
  Pose at(double seconds, {double speed = 1}) {
    if (keys.length == 1) return keys.first;
    final per = cycle / keys.length;
    final t = (seconds * speed) % cycle;
    final i = (t / per).floor() % keys.length;
    final f = (t - i * per) / per;
    // przytrzymanie w skrajnej pozycji, potem płynne przejście
    const hold = 0.22;
    final k = f < hold ? 0.0 : (f - hold) / (1 - hold);
    final e = 0.5 - math.cos(k * math.pi) / 2;
    return Pose.lerp(keys[i], keys[(i + 1) % keys.length], e);
  }
}
