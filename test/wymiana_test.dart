import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:forma/core/day_factors.dart';
import 'package:forma/core/exchange.dart';
import 'package:forma/core/models.dart';
import 'package:forma/core/store.dart';
import 'package:koofr_backup_ui/koofr_backup_ui.dart';

/// Kontrakt wymiany (WYMIANA.md w repozytorium Rytmu Snu) z perspektywy Formy.
void main() {
  final sources = [for (final s in FormaExchange().sources) s.$1];

  test('pobierane pliki wczytują się, a źródła zgadzają się z tym, czego szuka trener', () {
    final pulled = przykladyDlaZrodel(sources);
    expect(pulled, unorderedEquals(['czynniki-sen', 'czynniki-polar', 'czynniki-posilki']));
    final all = <String, Map<String, Map<String, Object?>>>{};
    for (final n in pulled) {
      final p = DayFactors.parse(Uint8List.fromList(utf8.encode(wymianaPrzyklady[n]!)));
      expect(p, isNotNull, reason: n);
      all[p!.$1] = p.$2;
    }
    final f = DayFactors(all);
    final day = DateTime(2025, 11, 19, 12);
    expect(f.sleep(day)?['sleep_min'], 412);
    expect(f.polarHrv(day), 38.4);
    expect(f.meals(day)?['kcal'], 2150);
  });

  test('wysyłane czynniki-forma są zgodne z kontraktem', () {
    final s = Store.instance;
    final start = DateTime(2026, 11, 19, 18);
    s.sessions.add(Session(
      id: 'w1',
      start: start,
      end: start.add(const Duration(minutes: 32)),
      kind: WorkoutKind.upper,
      title: 'Góra',
      done: const [],
      kcal: 260,
      rpe: 7,
    ));
    final bytes = buildFormaFactors(s);
    expect(sprawdzWymiane('czynniki-forma', bytes), isEmpty);
    final day = (jsonDecode(utf8.decode(bytes))['days'] as List).single as Map;
    expect(day['train_min'], 32);
    expect(day['end_h'], 18.53);
  });
}
