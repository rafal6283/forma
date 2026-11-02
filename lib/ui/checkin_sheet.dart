import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/store.dart';
import 'theme.dart';

/// Szybka ocena samopoczucia: jak się czujesz, co boli, ile spałeś (gdy brak danych z zegarka).
Future<void> showCheckIn(BuildContext context) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _CheckInSheet(),
    );

class _CheckInSheet extends StatefulWidget {
  const _CheckInSheet();

  @override
  State<_CheckInSheet> createState() => _CheckInSheetState();
}

class _CheckInSheetState extends State<_CheckInSheet> {
  late final CheckIn? prev = Store.instance.todayCheckIn;
  late int feel = prev?.feel ?? 3;
  late final Set<String> sore = {...?prev?.sore};
  late double sleep = prev?.sleepHours ?? 7;
  late bool askSleep = Store.instance.health.sleepHours == null;

  static const feelings = [
    (1, 'Kiepsko', Icons.sentiment_very_dissatisfied),
    (2, 'Słabo', Icons.sentiment_dissatisfied),
    (3, 'Zwykle', Icons.sentiment_neutral),
    (4, 'Dobrze', Icons.sentiment_satisfied),
    (5, 'Świetnie', Icons.sentiment_very_satisfied),
  ];

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Jak się dziś czujesz?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Row(children: [
              for (final f in feelings)
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() => feel = f.$1),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(children: [
                        Icon(f.$3, size: 34, color: feel == f.$1 ? C.accent : C.muted),
                        const SizedBox(height: 4),
                        Text(f.$2,
                            style: TextStyle(fontSize: 12, color: feel == f.$1 ? C.text : C.muted)),
                      ]),
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 16),
            const Text('Zakwasy lub zmęczenie', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final g in muscleGroups)
                FilterChip(
                  label: Text(g),
                  selected: sore.contains(g),
                  onSelected: (v) => setState(() => v ? sore.add(g) : sore.remove(g)),
                ),
            ]),
            if (askSleep) ...[
              const SizedBox(height: 16),
              Text('Sen: ${sleep.toStringAsFixed(1).replaceAll('.', ',')} h',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              Slider(value: sleep, min: 3, max: 11, divisions: 16, onChanged: (v) => setState(() => sleep = v)),
              Text('Z Health Connect (np. Rytm Snu, zegarek) sen wczyta się sam.',
                  style: TextStyle(color: C.muted, fontSize: 12)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: () async {
                await Store.instance.addCheckIn(CheckIn(DateTime.now(), feel, sore, askSleep ? sleep : null));
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Zapisz'),
            ),
          ]),
        ),
      );
}
