import 'dart:math' as math;

import 'rep_counter.dart';

/// Test ruchomości kamerą: głębokość przysiadu, uniesienie rąk nad głowę, skłon w przód (stopnie).
class MobilityResult {
  final DateTime at;
  final double? squatKnee; // najmniejszy kąt w kolanie w przysiadzie (mniej = głębiej)
  final double? overhead; // największy kąt bark (biodro–bark–łokieć) przy prostych rękach (więcej = lepiej)
  final double? fold; // najmniejszy kąt w biodrze (bark–biodro–kolano) w skłonie (mniej = lepiej)

  const MobilityResult(this.at, {this.squatKnee, this.overhead, this.fold});

  Map<String, Object?> toJson() => {
        'at': at.toIso8601String(),
        if (squatKnee != null) 'sq': squatKnee,
        if (overhead != null) 'oh': overhead,
        if (fold != null) 'fo': fold,
      };

  factory MobilityResult.fromJson(Map<String, dynamic> j) => MobilityResult(
        DateTime.parse(j['at'] as String),
        squatKnee: (j['sq'] as num?)?.toDouble(),
        overhead: (j['oh'] as num?)?.toDouble(),
        fold: (j['fo'] as num?)?.toDouble(),
      );

  /// Ocena 0–100 poszczególnych testów.
  static int squatScore(double knee) => ((150 - knee) / (150 - 60) * 100).clamp(0, 100).round();
  static int overheadScore(double sh) => ((sh - 120) / (175 - 120) * 100).clamp(0, 100).round();
  static int foldScore(double hip) => ((150 - hip) / (150 - 60) * 100).clamp(0, 100).round();

  int? get score {
    final s = [
      if (squatKnee != null) squatScore(squatKnee!),
      if (overhead != null) overheadScore(overhead!),
      if (fold != null) foldScore(fold!),
    ];
    return s.isEmpty ? null : (s.reduce((a, b) => a + b) / s.length).round();
  }

  /// Ćwiczenia na słabe miejsca (id z biblioteki).
  List<String> get focus => [
        if (squatKnee != null && squatScore(squatKnee!) < 70) ...['deep_squat_hold', 'hip_flexor_stretch', 'calf_stretch'],
        if (overhead != null && overheadScore(overhead!) < 70) ...['wall_angels', 'thoracic_open', 'band_dislocates', 'childs_pose'],
        if (fold != null && foldScore(fold!) < 70) ...['hamstring_stretch', 'standing_fold', 'runner_stretch'],
      ];
}

/// Najbardziej skrajna wartość z serii pomiarów, odporna na pojedyncze błędy detekcji (percentyl).
double? extreme(List<double> v, {required bool min}) {
  if (v.length < 5) return null;
  final s = [...v]..sort();
  final i = ((min ? 0.05 : 0.95) * (s.length - 1)).round();
  return s[i];
}

/// Kąty do testów ruchomości z punktów kamery (strona lepiej widoczna).
double? squatKneeAngle(Map<String, P3> p) => _best(p, (s) => _ang(p, 'hip$s', 'knee$s', 'ankle$s'), min: true);
double? overheadAngle(Map<String, P3> p) => _best(p, (s) {
      final el = _ang(p, 'shoulder$s', 'elbow$s', 'wrist$s');
      if (el == null || el < 150) return null; // ręce mają być proste
      return _ang(p, 'hip$s', 'shoulder$s', 'elbow$s');
    }, min: false);
double? foldHipAngle(Map<String, P3> p) => _best(p, (s) {
      final kn = _ang(p, 'hip$s', 'knee$s', 'ankle$s');
      if (kn == null || kn < 150) return null; // kolana proste
      return _ang(p, 'shoulder$s', 'hip$s', 'knee$s');
    }, min: true);

double? _ang(Map<String, P3> p, String a, String b, String c) {
  final pa = p[a], pb = p[b], pc = p[c];
  if (pa == null || pb == null || pc == null) return null;
  if (math.min(pa.conf, math.min(pb.conf, pc.conf)) < 0.5) return null;
  // tylko płaszczyzna obrazu: przy teście z boku głębia z modelu bardziej szkodzi, niż pomaga
  return angle3(P3(pa.x, pa.y), P3(pb.x, pb.y), P3(pc.x, pc.y));
}

double? _best(Map<String, P3> p, double? Function(String) f, {required bool min}) {
  final l = f('L'), r = f('R');
  if (l == null) return r;
  if (r == null) return l;
  return min ? math.min(l, r) : math.max(l, r);
}

/// Ocena postawy ze zdjęcia przodem i bokiem.
class PostureResult {
  final DateTime at;
  final double? shoulderTilt; // stopnie, + = prawy bark niżej
  final double? hipTilt;
  final double? headShift; // przesunięcie głowy w bok względem środka barków (% szerokości barków)
  final double? forwardHead; // stopnie: odchylenie linii ucho–bark od pionu (z boku), więcej = głowa bardziej w przód
  final double? roundedShoulders; // stopnie: bark przed biodrem (z boku)

  const PostureResult(this.at,
      {this.shoulderTilt, this.hipTilt, this.headShift, this.forwardHead, this.roundedShoulders});

  Map<String, Object?> toJson() => {
        'at': at.toIso8601String(),
        if (shoulderTilt != null) 'st': shoulderTilt,
        if (hipTilt != null) 'ht': hipTilt,
        if (headShift != null) 'hs': headShift,
        if (forwardHead != null) 'fh': forwardHead,
        if (roundedShoulders != null) 'rs': roundedShoulders,
      };

  factory PostureResult.fromJson(Map<String, dynamic> j) => PostureResult(
        DateTime.parse(j['at'] as String),
        shoulderTilt: (j['st'] as num?)?.toDouble(),
        hipTilt: (j['ht'] as num?)?.toDouble(),
        headShift: (j['hs'] as num?)?.toDouble(),
        forwardHead: (j['fh'] as num?)?.toDouble(),
        roundedShoulders: (j['rs'] as num?)?.toDouble(),
      );

  /// Opis i ocena każdej cechy: (nazwa, wartość tekstem, w normie?).
  List<(String, String, bool)> get findings => [
        if (shoulderTilt != null)
          ('Barki', shoulderTilt!.abs() < 2 ? 'równo' : '${shoulderTilt! > 0 ? 'prawy' : 'lewy'} niżej o ${shoulderTilt!.abs().toStringAsFixed(1)}°', shoulderTilt!.abs() < 2.5),
        if (hipTilt != null)
          ('Miednica', hipTilt!.abs() < 2 ? 'równo' : '${hipTilt! > 0 ? 'prawa' : 'lewa'} strona niżej o ${hipTilt!.abs().toStringAsFixed(1)}°', hipTilt!.abs() < 2.5),
        if (headShift != null)
          ('Głowa (przód)', headShift!.abs() < 5 ? 'na środku' : 'przesunięta w ${headShift! > 0 ? 'prawo' : 'lewo'} o ${headShift!.abs().round()}%', headShift!.abs() < 7),
        if (forwardHead != null)
          ('Głowa (bok)', forwardHead! < 10 ? 'nad barkami' : 'wysunięta w przód o ${forwardHead!.round()}°', forwardHead! < 15),
        if (roundedShoulders != null)
          ('Barki (bok)', roundedShoulders! < 6 ? 'nad biodrami' : 'zaokrąglone w przód o ${roundedShoulders!.round()}°', roundedShoulders! < 10),
      ];

  List<String> get focus => [
        if ((forwardHead ?? 0) >= 15) ...['wall_angels', 'prone_y'],
        if ((roundedShoulders ?? 0) >= 10) ...['band_pull_apart', 'chest_stretch', 'thoracic_open'],
        if ((shoulderTilt ?? 0).abs() >= 2.5 || (hipTilt ?? 0).abs() >= 2.5) ...['side_plank', 'side_bend', 'bird_dog'],
      ];

  /// Zdjęcie przodem: [p] — punkty kamery (obraz nieodbity: lewa strona osoby po prawej stronie zdjęcia).
  static PostureResult front(Map<String, P3> p, {DateTime? at}) {
    double? tilt(String a) {
      final l = p['${a}L'], r = p['${a}R'];
      if (l == null || r == null || l.conf < 0.5 || r.conf < 0.5) return null;
      // dodatni = prawa strona osoby (po lewej na zdjęciu) niżej
      return math.atan2(r.y - l.y, (l.x - r.x).abs()) * 180 / math.pi;
    }

    double? shift;
    final n = p['nose'], sl = p['shoulderL'], sr = p['shoulderR'];
    if (n != null && sl != null && sr != null) {
      final w = (sl.x - sr.x).abs();
      if (w > 1) shift = ((sl.x + sr.x) / 2 - n.x) / w * 100; // + = w prawo osoby
    }
    return PostureResult(at ?? DateTime.now(), shoulderTilt: tilt('shoulder'), hipTilt: tilt('hip'), headShift: shift);
  }

  /// Zdjęcie bokiem: kąt ucho–bark i bark–biodro względem pionu (strona lepiej widoczna).
  static PostureResult side(Map<String, P3> p, {DateTime? at}) {
    String s = 'L';
    double c(String k) => p[k]?.conf ?? 0;
    if (c('earR') + c('shoulderR') + c('hipR') > c('earL') + c('shoulderL') + c('hipL')) s = 'R';
    final ear = p['ear$s'], sh = p['shoulder$s'], hip = p['hip$s'];
    double? lean(P3? top, P3? bottom) {
      if (top == null || bottom == null) return null;
      // kierunek „w przód” = strona, w którą patrzy nos
      final nose = p['nose'];
      final fwd = nose == null ? 1.0 : (nose.x >= bottom.x ? 1.0 : -1.0);
      return math.atan2((top.x - bottom.x) * fwd, bottom.y - top.y) * 180 / math.pi;
    }

    return PostureResult(at ?? DateTime.now(), forwardHead: lean(ear, sh), roundedShoulders: lean(sh, hip));
  }

  PostureResult merge(PostureResult o) => PostureResult(at,
      shoulderTilt: shoulderTilt ?? o.shoulderTilt,
      hipTilt: hipTilt ?? o.hipTilt,
      headShift: headShift ?? o.headShift,
      forwardHead: forwardHead ?? o.forwardHead,
      roundedShoulders: roundedShoulders ?? o.roundedShoulders);
}

/// Zdjęcie sylwetki (plik w katalogu aplikacji).
class BodyPhoto {
  final DateTime at;
  final String file; // nazwa pliku w katalogu zdjęć
  final String view; // 'front' | 'side' | 'back'
  const BodyPhoto(this.at, this.file, this.view);

  Map<String, Object?> toJson() => {'at': at.toIso8601String(), 'f': file, 'v': view};
  factory BodyPhoto.fromJson(Map<String, dynamic> j) =>
      BodyPhoto(DateTime.parse(j['at'] as String), j['f'] as String, j['v'] as String? ?? 'front');
}

/// Obwody ciała (cm).
class Measurement {
  final DateTime at;
  final Map<String, double> cm; // waist, hips, chest, arm, thigh
  const Measurement(this.at, this.cm);

  static const labels = {'waist': 'Pas', 'hips': 'Biodra', 'chest': 'Klatka', 'arm': 'Ramię', 'thigh': 'Udo'};

  Map<String, Object?> toJson() => {'at': at.toIso8601String(), 'cm': cm};
  factory Measurement.fromJson(Map<String, dynamic> j) => Measurement(DateTime.parse(j['at'] as String),
      ((j['cm'] as Map?) ?? const {}).map((k, v) => MapEntry(k as String, (v as num).toDouble())));
}
