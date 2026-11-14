import 'dart:convert';
import 'dart:typed_data';

String isoDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Czynniki dnia z innych aplikacji tej samej osoby (format „czynniki-dnia”): źródło → dzień → wartości.
class DayFactors {
  final Map<String, Map<String, Map<String, Object?>>> bySource;
  const DayFactors(this.bySource);
  static const empty = DayFactors({});

  Map<String, Object?>? _get(String source, DateTime d) => bySource[source]?[isoDay(d)];

  /// Sen z Rytmu Snu (noc kończąca się danego dnia).
  Map<String, Object?>? sleep(DateTime d) => _get('rytm-snu', d);

  /// HRV z Polar EKG (ms) danego dnia.
  double? polarHrv(DateTime d) => (_get('polar-ekg', d)?['hrv'] as num?)?.toDouble();

  /// Historia HRV z Polar EKG (ostatnie [days] dni przed [now], bez dnia bieżącego).
  List<double> polarHrvHistory(DateTime now, {int days = 30}) => [
        for (var i = 1; i <= days; i++)
          if (polarHrv(now.subtract(Duration(days: i))) case final v?) v,
      ];

  /// Posiłki z Dziennika talerza danego dnia.
  Map<String, Object?>? meals(DateTime d) => _get('dziennik-talerza', d);

  bool get isEmpty => bySource.values.every((m) => m.isEmpty);

  Map<String, Object?> toJson() => bySource;

  factory DayFactors.fromJson(Map<String, Object?>? j) => DayFactors({
        for (final e in (j ?? const {}).entries)
          e.key: {
            for (final d in ((e.value as Map?) ?? const {}).entries)
              d.key as String: ((d.value as Map?) ?? const {}).cast<String, Object?>(),
          },
      });

  /// Odczyt pliku „czynniki-dnia” (zwraca źródło i dni) albo null, gdy to inny format.
  static (String, Map<String, Map<String, Object?>>)? parse(Uint8List data) {
    try {
      final j = jsonDecode(utf8.decode(data)) as Map;
      if (j['format'] != 'czynniki-dnia') return null;
      final src = j['source'] as String? ?? '';
      final days = <String, Map<String, Object?>>{};
      for (final d in (j['days'] as List? ?? const [])) {
        final m = (d as Map).cast<String, Object?>();
        final date = m['date'] as String?;
        if (date != null) days[date] = m;
      }
      return (src, days);
    } catch (_) {
      return null;
    }
  }
}
