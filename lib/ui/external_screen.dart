import 'package:flutter/material.dart';

import '../core/activity_import.dart';
import '../core/store.dart';
import 'theme.dart';

/// Biegi, rower i inne aktywności z zegarka (Strava, Health Connect).
class ExternalScreen extends StatefulWidget {
  const ExternalScreen({super.key});

  @override
  State<ExternalScreen> createState() => _ExternalScreenState();
}

class _ExternalScreenState extends State<ExternalScreen> {
  bool busy = false;

  Future<void> _run() async {
    setState(() => busy = true);
    final (n, err) = await ActivityImport.instance.run();
    if (!mounted) return;
    setState(() => busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(err != null ? 'Część się nie udała:\n$err' : (n == 0 ? 'Nic nowego.' : 'Dodano $n aktywności.')),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = Store.instance;
    final list = s.external.reversed.toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Aktywności z zegarka')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
        Text(
          'Bieganie, rower czy spacer zapisane zegarkiem (Strava, Health Connect — np. przez Gadgetbridge) '
          'liczą się do obciążenia tygodnia, zmęczenia mięśni, kalendarza i poziomu. '
          'Trener weźmie je pod uwagę przy doborze treningu. Aktywności pokrywające się z treningiem w Formie są pomijane.',
          style: TextStyle(color: C.muted, height: 1.35),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: busy ? null : _run,
          icon: busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.sync),
          label: const Text('Importuj teraz'),
        ),
        const SizedBox(height: 12),
        if (list.isEmpty)
          Text('Brak zaimportowanych aktywności. Połącz Stravę albo włącz Health Connect w ustawieniach.',
              style: TextStyle(color: C.muted))
        else
          Card(
            child: Column(children: [
              for (final a in list.take(100))
                ListTile(
                  leading: Icon(switch (a.sportLabel) {
                    'Bieg' => Icons.directions_run,
                    'Rower' => Icons.directions_bike,
                    'Spacer' || 'Wędrówka' => Icons.directions_walk,
                    'Pływanie' => Icons.pool,
                    _ => Icons.sports,
                  }),
                  title: Text(a.name.isEmpty ? a.sportLabel : a.name),
                  subtitle: Text(
                    '${fmtDate(a.start)} · ${a.sportLabel} · ${a.minutes} min'
                    '${a.km != null ? ' · ${a.km!.toStringAsFixed(1)} km' : ''}'
                    '${a.avgHr != null ? ' · ${a.avgHr} bpm' : ''} · ${a.source == 'strava' ? 'Strava' : 'Health'}',
                    style: TextStyle(color: C.muted, fontSize: 12),
                  ),
                  trailing: IconButton(
                    tooltip: 'Usuń',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      setState(() => s.external.remove(a));
                      await s.save();
                    },
                  ),
                ),
            ]),
          ),
      ]),
    );
  }
}
