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

  /// Dodatkowe wyprostowanie każdej stopy osobno (bliższa, dalsza) — np. w klęku jednonóż.
  final List<double> fq;
  final bool front, back;

  /// Widok z przodu: golenie zgięte do tyłu (poza płaszczyznę obrazu), np. deska bokiem na kolanach.
  final bool kneesBack;

  /// Widok z przodu: skłon tułowia do przodu (stopnie) — tułów, głowa i barki wychodzą przed płaszczyznę obrazu.
  final double fold;

  /// Ruch poza płaszczyzną: odchylenie kończyn na bok [ręka N, ręka F, noga N, noga F] (stopnie).
  final List<double> ab;

  /// Skręt barków wokół kręgosłupa (stopnie, + = bliższy bark do przodu).
  final double rot;

  /// Łopatki: wysunięcie (sp, do przodu ciała) i uniesienie (se, wzdłuż tułowia), w metrach.
  final double sp, se;

  /// Kolano na bok wokół osi biodro–kostka [N, F] (stopnie, + = na zewnątrz; stopa zostaje w miejscu).
  final List<double> kr;

  /// Sam skręt klatki i głowy (stopnie), bez ruchu rąk — np. otwieranie klatki z ręką do sufitu.
  final double tw;

  const Pose({
    this.t = 180,
    double? h,
    this.an = const [8, 12],
    this.af = const [-8, -4],
    this.ln = const [2, 0],
    this.lf = const [-2, 0],
    this.fp = 0,
    this.fq = const [0, 0],
    this.lift = 0,
    this.x = 0,
    this.front = false,
    this.back = false,
    this.kneesBack = false,
    this.fold = 0,
    this.ab = const [0, 0, 0, 0],
    this.rot = 0,
    this.sp = 0,
    this.se = 0,
    this.kr = const [0, 0],
    this.tw = 0,
  }) : h = h ?? t;

  bool get outOfPlane => rot != 0 || sp != 0 || se != 0 || ab.any((a) => a != 0) || kr.any((a) => a != 0);

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
      fq: _l(j['fq'], const [0, 0]),
      lift: n('lift', 0),
      x: n('x', 0),
      front: j['view'] == 'front',
      back: j['back'] == true,
      kneesBack: j['kb'] == true,
      fold: n('fold', 0),
      ab: _l(j['ab'], const [0, 0, 0, 0]),
      rot: n('rot', 0),
      sp: n('sp', 0),
      se: n('se', 0),
      kr: _l(j['kr'], const [0, 0]),
      tw: n('tw', 0),
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
        fq: [fq[1], fq[0]],
        lift: lift,
        x: front ? -x : x,
        front: front,
        back: back,
        kneesBack: kneesBack,
        fold: fold,
        ab: [ab[1], ab[0], ab[3], ab[2]],
        rot: -rot,
        sp: sp,
        se: se,
        kr: [kr[1], kr[0]],
        tw: -tw,
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
      fq: [lin(a.fq[0], b.fq[0]), lin(a.fq[1], b.fq[1])],
      lift: lin(a.lift, b.lift),
      x: lin(a.x, b.x),
      front: k < 0.5 ? a.front : b.front,
      back: k < 0.5 ? a.back : b.back,
      kneesBack: k < 0.5 ? a.kneesBack : b.kneesBack,
      fold: lin(a.fold, b.fold),
      ab: [for (var i = 0; i < 4; i++) lin(a.ab[i], b.ab[i])],
      rot: lin(a.rot, b.rot),
      sp: lin(a.sp, b.sp),
      se: lin(a.se, b.se),
      kr: [lin(a.kr[0], b.kr[0]), lin(a.kr[1], b.kr[1])],
      tw: lin(a.tw, b.tw),
    );
  }
}

/// Pozycje stawów; klucze jak w tool/figure.py (haN = dłoń bliższa, toF = palce dalszej stopy…).
class Joints {
  final Map<String, Offset> p;
  final bool front, back;
  final double headDir;
  final bool kneesBack;

  /// Głębokość (z, do widza) punktów wysuniętych przed płaszczyznę obrazu (skłon w widoku z przodu).
  final Map<String, double> z;
  final double fold;

  /// Skręt barków (stopnie) — tułów i głowa obracają się razem z nimi.
  final double rot;
  Joints(this.p, this.front, this.back, this.headDir,
      {this.kneesBack = false, this.z = const {}, this.fold = 0, this.rot = 0});

  Offset operator [](String k) => p[k]!;

  Joints shifted(Offset d) =>
      Joints(p.map((k, v) => MapEntry(k, v + d)), front, back, headDir,
          kneesBack: kneesBack, z: z, fold: fold, rot: rot);

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
      var an = kn + _dir(leg[1]) * Body.shin;
      final Offset toe;
      if (s.front && s.kneesBack) {
        // goleń za plecami: w rzucie z przodu kostka i palce tuż przy kolanie
        an = kn + const Offset(0, 0.01);
        toe = an;
      } else if (s.front) {
        // but od przodu: przedłużenie goleni (pod kostką, gdy stoi), lekko na zewnątrz
        toe = an + _dir(leg[1]) * 0.045 + perp * (sgn * 0.02);
      } else {
        // palcami do przodu ciała; na plecach postać jest lustrzana. fp > 0 = wspięcie na palce.
        final fp = s.fp + s.fq[near ? 0 : 1];
        toe = an + _dir(s.back ? leg[1] - 90 + fp : leg[1] + 90 - fp) * Body.foot;
      }
      m.addAll({'sh$side': sh, 'el$side': el, 'ha$side': ha, 'hp$side': hp, 'kn$side': kn, 'an$side': an, 'to$side': toe});
    }
    final z = <String, double>{};
    if (s.front && s.fold != 0) _fold(s, m, z);
    if (s.outOfPlane) _outOfPlane(s, m, z);
    return Joints(m, s.front, s.back, s.h, kneesBack: s.kneesBack, z: z, fold: s.front ? s.fold : 0, rot: s.rot + s.tw);
  }

  static void _fold(Pose s, Map<String, Offset> m, Map<String, double> z) {
    final hip = m['hip']!;
    // skłon w przód: tułów, głowa i barki obracają się wokół osi bioder do widza; ręce zwisają w płaszczyźnie obrazu
    final f = s.fold * math.pi / 180;
    for (final k in ['neck', 'head', 'shN', 'shF']) {
      final dy = m[k]!.dy - hip.dy;
      m[k] = Offset(m[k]!.dx, hip.dy + dy * math.cos(f));
      z[k] = -dy * math.sin(f);
    }
    for (final near in [true, false]) {
      final side = near ? 'N' : 'F';
      final arm = near ? s.an : [-s.af[0], -s.af[1]];
      final el = m['sh$side']! + _dir(arm[0]) * Body.upper;
      m['el$side'] = el;
      m['ha$side'] = el + _dir(arm[1]) * Body.fore;
      z['el$side'] = z['sh$side']!;
      z['ha$side'] = z['sh$side']!;
    }
  }

  /// Głębokość, którą widok 3D nadaje stawom bez ruchu poza płaszczyzną (jak lift3d).
  static double baseZ(String k, bool front) {
    if (front || !(k.endsWith('N') || k.endsWith('F'))) return 0;
    final arm = k.startsWith('sh') || k.startsWith('el') || k.startsWith('ha');
    return (k.endsWith('N') ? 1 : -1) * (arm ? Body.shoulderW : Body.hipW + 0.01);
  }

  /// Łopatki, odchylenie kończyn na bok i skręt barków — liczone w 3D (jak tool/figure.py).
  static void _outOfPlane(Pose s, Map<String, Offset> m, Map<String, double> z) {
    final front = s.front;
    final q = <String, List<double>>{
      for (final e in m.entries) e.key: [e.value.dx, e.value.dy, baseZ(e.key, front) + (z[e.key] ?? 0)],
    };
    List<double> add(List<double> a, List<double> b, [double k = 1]) => [for (var i = 0; i < 3; i++) a[i] + b[i] * k];
    double dot(List<double> a, List<double> b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
    List<double> unit(List<double> a) {
      final n = math.sqrt(dot(a, a));
      return n == 0 ? a : [a[0] / n, a[1] / n, a[2] / n];
    }

    final neck = q['neck']!;
    final u = unit(add(neck, q['hip']!, -1));
    List<double> f, lat;
    if (front) {
      f = [0, 0, 1];
      final sh = q['shN']!;
      lat = (sh[0] - neck[0]) * -u[1] + (sh[1] - neck[1]) * u[0] >= 0 ? [-u[1], u[0], 0] : [u[1], -u[0], 0];
    } else {
      f = s.back ? [u[1], -u[0], 0] : [-u[1], u[0], 0];
      lat = [0, 0, 1];
    }
    const arms = ['shN', 'elN', 'haN', 'shF', 'elF', 'haF'];
    if (s.sp != 0 || s.se != 0) {
      for (final k in arms) {
        q[k] = add(add(q[k]!, f, s.sp), u, s.se);
      }
    }
    // kolano na bok wokół osi biodro–kostka (stopa zostaje w miejscu)
    for (var i = 0; i < 2; i++) {
      final a = s.kr[i];
      if (a == 0) continue;
      final sd = i == 0 ? 'N' : 'F';
      final hp = q['hp$sd']!;
      final ax = unit(add(q['an$sd']!, hp, -1));
      final v = add(q['kn$sd']!, hp, -1);
      final par = dot(v, ax);
      final perp = add(v, ax, -par);
      final r = math.sqrt(dot(perp, perp));
      if (r < 1e-6) continue;
      final e1 = [perp[0] / r, perp[1] / r, perp[2] / r];
      final out = [for (final c in lat) c * (i == 0 ? 1 : -1)];
      final e2 = unit(add(add(out, ax, -dot(out, ax)), e1, -dot(out, e1)));
      final ca = math.cos(a * math.pi / 180), sa = math.sin(a * math.pi / 180);
      q['kn$sd'] = add(add(add(hp, ax, par), e1, r * ca), e2, r * sa);
    }
    const limbs = [
      ('shN', ['elN', 'haN'], 1.0),
      ('shF', ['elF', 'haF'], -1.0),
      ('hpN', ['knN', 'anN', 'toN'], 1.0),
      ('hpF', ['knF', 'anF', 'toF'], -1.0),
    ];
    for (var i = 0; i < 4; i++) {
      final a = s.ab[i];
      if (a == 0) continue;
      final (root, pts, sd) = limbs[i];
      final r = q[root]!;
      final d1 = unit(add(q[pts[0]]!, r, -1));
      final side = front ? f : [lat[0] * sd, lat[1] * sd, lat[2] * sd];
      final ca = math.cos(a * math.pi / 180), sa = math.sin(a * math.pi / 180);
      for (final k in pts) {
        final v = add(q[k]!, r, -1);
        final al = dot(v, d1);
        final rest = add(v, d1, -al);
        q[k] = add(add(add(r, rest), d1, al * ca), side, al * sa);
      }
    }
    if (s.rot != 0) {
      final c = math.cos(s.rot * math.pi / 180), sn = math.sin(s.rot * math.pi / 180);
      for (final k in arms) {
        final v = add(q[k]!, neck, -1);
        final a = dot(v, u), b = dot(v, f), cc = dot(v, lat);
        q[k] = add(add(add(neck, u, a), f, b * c + cc * sn), lat, cc * c - b * sn);
      }
    }
    q.forEach((k, v) {
      m[k] = Offset(v[0], v[1]);
      final dz = v[2] - baseZ(k, front);
      if (dz.abs() > 1e-9) {
        z[k] = dz;
      } else {
        z.remove(k);
      }
    });
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

  /// Ruch ciągły (krążenia): bez zatrzymań w klatkach, gładka krzywa przez wszystkie klatki.
  final bool flow;

  /// Zalecany obrót kamery (radiany) — dla ruchów poza płaszczyzną widoku z boku.
  final double? cam;

  /// Podpora wskazana ręcznie (np. kark w hip thruście); 'none' = bez przypinania.
  final String? pin;

  /// Dłonie/stopy trzymane cały czas w jednym miejscu (np. dłonie na krześle w pompkach).
  final List<String> fix;

  FigAnim(this.keys, this.cycle,
      {this.hands = false, this.props = const [], this.flow = false, this.cam, this.pin, this.fix = const []});

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
      flow: j['flow'] == true,
      cam: (j['cam'] as num?)?.toDouble(),
      pin: j['pin'] as String?,
      fix: ((j['fix'] as List?) ?? const []).cast<String>(),
    );
  }

  /// (klatka, postęp 0…1 przejścia do następnej) w chwili [seconds] — ten sam podział co w [at].
  (int, double) phase(double seconds, {double speed = 1}) {
    if (keys.length == 1) return (0, 0);
    final per = cycle / keys.length;
    final t = (seconds * speed) % cycle;
    final i = (t / per).floor() % keys.length;
    final f = (t - i * per) / per;
    if (flow) return (i, f);
    const hold = 0.22;
    final k = f < hold ? 0.0 : (f - hold) / (1 - hold);
    return (i, 0.5 - math.cos(k * math.pi) / 2);
  }

  /// Poza w chwili [seconds] (pętla); na każdą klatkę przypada równa część cyklu.
  Pose at(double seconds, {double speed = 1}) {
    if (keys.length == 1) return keys.first;
    final per = cycle / keys.length;
    final t = (seconds * speed) % cycle;
    final i = (t / per).floor() % keys.length;
    final f = (t - i * per) / per;
    final n = keys.length;
    if (flow) {
      // Catmull-Rom (schemat Barry'ego-Goldmana) — stała prędkość, bez szarpnięć na klatkach
      final p0 = keys[(i - 1 + n) % n], p1 = keys[i], p2 = keys[(i + 1) % n], p3 = keys[(i + 2) % n];
      final a1 = Pose.lerp(p0, p1, f + 1), a2 = Pose.lerp(p1, p2, f), a3 = Pose.lerp(p2, p3, f - 1);
      return Pose.lerp(Pose.lerp(a1, a2, (f + 1) / 2), Pose.lerp(a2, a3, f / 2), f);
    }
    // przytrzymanie w skrajnej pozycji, potem płynne przejście
    const hold = 0.22;
    final k = f < hold ? 0.0 : (f - hold) / (1 - hold);
    final e = 0.5 - math.cos(k * math.pi) / 2;
    return Pose.lerp(keys[i], keys[(i + 1) % keys.length], e);
  }

  /// Bieżący odcinek ruchu: poza docelowa i „prędkość” 0…1 (0 w przytrzymaniu, 1 w połowie przejścia).
  (Pose to, double move) motion(double seconds, {double speed = 1}) {
    if (keys.length == 1) return (keys.first, 0);
    final per = cycle / keys.length;
    final t = (seconds * speed) % cycle;
    final i = (t / per).floor() % keys.length;
    final f = (t - i * per) / per;
    if (flow) return (keys[(i + 1) % keys.length], 1.0);
    const hold = 0.22;
    final k = f < hold ? 0.0 : (f - hold) / (1 - hold);
    return (keys[(i + 1) % keys.length], f < hold ? 0 : math.sin(k * math.pi));
  }
}
