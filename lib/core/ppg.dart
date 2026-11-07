import 'dart:math' as math;

/// Wynik pomiaru tętna i HRV palcem na aparacie (fotopletyzmografia).
class PpgResult {
  final int bpm;
  final double? rmssd;
  final List<double> rr; // odstępy między uderzeniami (ms) po odrzuceniu artefaktów
  final double quality; // 0..1 — udział czystych uderzeń
  const PpgResult(this.bpm, this.rmssd, this.rr, this.quality);
}

/// Analiza sygnału jasności palca: wygładzenie, usunięcie trendu, szczyty, odstępy RR, RMSSD.
/// [t] — czas próbek w ms, [v] — średnia jasność (czerwień) kadru.
class Ppg {
  /// Sygnał po usunięciu trendu (średnia ruchoma ~1,6 s) i wygładzeniu; odwrócony, bo krew przyciemnia palec.
  static List<double> filtered(List<double> t, List<double> v) {
    final n = v.length;
    if (n < 10) return const [];
    final dt = (t.last - t.first) / (n - 1);
    final fs = 1000 / math.max(1, dt);
    final w = math.max(3, (fs * 1.6).round());
    final smooth = math.max(1, (fs / 7).round()); // ~140 ms
    final out = List<double>.filled(n, 0);
    // prefix sums
    final ps = List<double>.filled(n + 1, 0);
    for (var i = 0; i < n; i++) {
      ps[i + 1] = ps[i] + v[i];
    }
    double mean(int a, int b) => (ps[b] - ps[a]) / (b - a);
    for (var i = 0; i < n; i++) {
      final a = math.max(0, i - w ~/ 2), b = math.min(n, i + w ~/ 2 + 1);
      final sa = math.max(0, i - smooth ~/ 2), sb = math.min(n, i + smooth ~/ 2 + 1);
      out[i] = -(mean(sa, sb) - mean(a, b));
    }
    return out;
  }

  /// Momenty uderzeń (ms) — szczyty z interpolacją paraboliczną; odstęp min. 330 ms (do 180 bpm).
  static List<double> beats(List<double> t, List<double> v) {
    final f = filtered(t, v);
    if (f.isEmpty) return const [];
    final out = <double>[];
    // próg adaptacyjny: 35% odchylenia w oknie ~3 s
    final n = f.length;
    final dt = (t.last - t.first) / (n - 1);
    final win = math.max(10, (3000 / math.max(1, dt)).round());
    for (var i = 1; i < n - 1; i++) {
      if (!(f[i] > f[i - 1] && f[i] >= f[i + 1])) continue;
      final a = math.max(0, i - win ~/ 2), b = math.min(n, i + win ~/ 2);
      var s = 0.0;
      for (var k = a; k < b; k++) {
        s += f[k] * f[k];
      }
      final sd = math.sqrt(s / (b - a));
      if (f[i] < 0.35 * sd) continue;
      // czy to największy szczyt w promieniu 330 ms
      var best = true;
      for (var k = i - 1; k >= 0 && t[i] - t[k] < 330; k--) {
        if (f[k] > f[i]) best = false;
      }
      for (var k = i + 1; k < n && t[k] - t[i] < 330; k++) {
        if (f[k] > f[i]) best = false;
      }
      if (!best) continue;
      final y0 = f[i - 1], y1 = f[i], y2 = f[i + 1];
      final den = y0 - 2 * y1 + y2;
      final off = den == 0 ? 0.0 : (0.5 * (y0 - y2) / den).clamp(-0.5, 0.5);
      final tt = t[i] + off * (t[i + 1] - t[i - 1]) / 2;
      if (out.isNotEmpty && tt - out.last < 330) continue;
      out.add(tt);
    }
    return out;
  }

  /// Pełna analiza. Null, gdy sygnał jest za słaby (np. palec nie zakrywa obiektywu).
  static PpgResult? analyze(List<double> t, List<double> v) {
    final b = beats(t, v);
    if (b.length < 8) return null;
    final raw = [for (var i = 1; i < b.length; i++) b[i] - b[i - 1]];
    final sorted = [...raw]..sort();
    final med = sorted[sorted.length ~/ 2];
    if (med < 333 || med > 1500) return null;
    // artefakty: odstęp różny od mediany o > 25% (przy RMSSD liczymy tylko pary sąsiednich czystych)
    final ok = [for (final r in raw) (r - med).abs() <= 0.25 * med];
    final clean = [for (var i = 0; i < raw.length; i++) if (ok[i]) raw[i]];
    final quality = clean.length / raw.length;
    var s = 0.0, n = 0;
    for (var i = 1; i < raw.length; i++) {
      if (ok[i] && ok[i - 1]) {
        final d = raw[i] - raw[i - 1];
        s += d * d;
        n++;
      }
    }
    final rmssd = n >= 10 && quality >= 0.7 ? math.sqrt(s / n) : null;
    return PpgResult((60000 / med).round(), rmssd, clean, quality);
  }
}
