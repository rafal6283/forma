import 'dart:convert';
import 'dart:typed_data';

import 'package:koofr_backup_ui/koofr_backup_ui.dart';

import 'day_factors.dart';
import 'store.dart';

/// Moje treningi jako „czynniki-dnia” dla innych aplikacji (np. Rytm Snu: trening a sen).
List<int> buildFormaFactors(Store s) {
  final days = <String, Map<String, Object?>>{};
  for (final x in s.sessions) {
    final m = days.putIfAbsent(isoDay(x.start), () => {'date': isoDay(x.start), 'train_min': 0, 'train_kcal': 0});
    m['train_min'] = (m['train_min'] as int) + x.duration.inMinutes;
    m['train_kcal'] = (m['train_kcal'] as int) + x.kcal.round();
    m['rpe_max'] = [(m['rpe_max'] as int?) ?? 0, x.rpe].reduce((a, b) => a > b ? a : b);
    m['end_h'] = double.parse((x.end.hour + x.end.minute / 60).toStringAsFixed(2));
  }
  for (final x in s.external) {
    final m = days.putIfAbsent(isoDay(x.start), () => {'date': isoDay(x.start), 'train_min': 0, 'train_kcal': 0});
    m['other_min'] = ((m['other_min'] as int?) ?? 0) + x.minutes;
  }
  final keys = days.keys.toList()..sort();
  return utf8.encode(jsonEncode({
    'format': 'czynniki-dnia',
    'version': 1,
    'source': 'forma',
    'exported_at': DateTime.now().millisecondsSinceEpoch,
    'days': [for (final k in keys) days[k]],
  }));
}

/// Wymiana z innymi aplikacjami tej samej osoby przez Koofr.
class FormaExchange extends ExchangeAdapter {
  @override
  String? get publishes => 'Treningi (minuty, kalorie, wysiłek, godzina końca) — dla Rytmu Snu i Dziennika talerza';

  @override
  List<(String, String)> get sources => const [
        ('czynniki-sen', 'Rytm Snu — sen do oceny gotowości'),
        ('czynniki-polar', 'Polar EKG — HRV z paska'),
        ('czynniki-posilki', 'Dziennik talerza — kalorie i posiłki'),
      ];

  @override
  Future<Map<String, List<int>?>> export() async => {'czynniki-forma': buildFormaFactors(Store.instance)};

  @override
  Future<void> import(String name, Uint8List data) async {
    final p = DayFactors.parse(data);
    if (p == null) return;
    final (src, days) = p;
    final s = Store.instance;
    final all = {...s.dayFactors.bySource, src.isEmpty ? name : src: days};
    s.dayFactors = DayFactors(all);
    await s.save();
  }
}
