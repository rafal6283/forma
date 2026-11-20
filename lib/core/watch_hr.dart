import 'models.dart';
import 'trainer.dart';

/// Tętno z zegarka bez nadawania przez Bluetooth (np. Huawei Watch GT 2): po treningu próbki z Health Connect
/// (Huawei Zdrowie → Health Sync → Health Connect) wpisywane do sesji jak z opaski, oznaczone jako „z zegarka”.
///
/// Próbki zegarka bywają rzadkie (co sekundę w trybie treningu na zegarku, co kilka minut poza nim), więc
/// przerwy do [maxGap] wypełniamy ostatnią wartością, dłuższe zostają puste (0).
class WatchHr {
  final List<int> hr; // co 5 s od startu sesji (0 = brak)
  final int avg, max;
  final List<int> zones; // sekundy w strefach 1–5
  final double coverage; // część treningu z tętnem (0–1)
  const WatchHr(this.hr, this.avg, this.max, this.zones, this.coverage);

  static WatchHr? fromSamples(List<(DateTime, int)> samples, DateTime start, DateTime end, int maxHr,
      {Duration maxGap = const Duration(minutes: 3)}) {
    final pts = samples.where((s) => s.$2 >= 30 && s.$2 <= 240).toList()..sort((a, b) => a.$1.compareTo(b.$1));
    final n = end.difference(start).inSeconds ~/ 5;
    if (n <= 0) return null;
    final hr = List<int>.filled(n, 0);
    var k = 0;
    (DateTime, int)? last;
    for (var i = 0; i < n; i++) {
      final t = start.add(Duration(seconds: i * 5 + 5));
      while (k < pts.length && !pts[k].$1.isAfter(t)) {
        last = pts[k];
        k++;
      }
      if (last != null && t.difference(last.$1) <= maxGap) hr[i] = last.$2;
    }
    final valid = hr.where((v) => v > 0).toList();
    if (valid.length < 3) return null;
    final zones = List<int>.filled(5, 0);
    for (final v in valid) {
      zones[Trainer.zone(v, maxHr) - 1] += 5;
    }
    return WatchHr(hr, (valid.reduce((a, b) => a + b) / valid.length).round(), valid.reduce((a, b) => a > b ? a : b),
        zones, valid.length / n);
  }

  /// Sesja z tętnem z zegarka (reszta bez zmian).
  Session apply(Session s) => Session.fromJson({
        ...s.toJson(),
        'hr': hr,
        'avgHr': avg,
        'maxHr': max,
        'zones': zones,
        'hrSrc': 'watch',
      });
}
