import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/hr.dart';
import '../core/models.dart';
import '../core/store.dart';
import '../core/trainer.dart';
import 'theme.dart';
import 'widgets.dart';

/// Poranny pomiar HRV (RMSSD) z odstępów RR opaski — 2 minuty w spokoju.
class HrvScreen extends StatefulWidget {
  const HrvScreen({super.key});

  @override
  State<HrvScreen> createState() => _HrvScreenState();
}

class _HrvScreenState extends State<HrvScreen> {
  static const total = 120;
  final hr = HrService.instance;
  final rr = <double>[];
  final bpms = <int>[];
  StreamSubscription<double>? _sub;
  Timer? _timer;
  int elapsed = 0;
  bool running = false;
  double? result;
  int? restHr;

  @override
  void dispose() {
    _sub?.cancel();
    _timer?.cancel();
    WakelockPlus.disable();
    super.dispose();
  }

  void _start() {
    rr.clear();
    bpms.clear();
    result = null;
    elapsed = 0;
    running = true;
    WakelockPlus.enable();
    _sub = hr.rr.stream.listen(rr.add);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final b = hr.freshBpm;
      if (b != null) bpms.add(b);
      setState(() => elapsed++);
      if (elapsed >= total) _finish();
    });
    setState(() {});
  }

  void _finish() {
    _timer?.cancel();
    _sub?.cancel();
    WakelockPlus.disable();
    running = false;
    // pierwsze 20 s to uspokojenie — pomijamy
    final skip = rr.length > 40 ? (rr.length * 20 / total).floor() : 0;
    result = Trainer.rmssd(rr.sublist(skip));
    if (bpms.isNotEmpty) {
      final s = [...bpms]..sort();
      restHr = s[(s.length * 0.2).floor()];
    }
    setState(() {});
  }

  Future<void> _save() async {
    await Store.instance.addHrv(HrvMeasure(DateTime.now(), result!, restHr ?? 0, 'pasek'));
    if (mounted) {
      toast(context, 'Zapisano pomiar HRV');
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hist = Store.instance.hrv.where((h) => DateTime.now().difference(h.at).inDays < 30).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Pomiar HRV')),
      body: ListenableBuilder(
        listenable: hr,
        builder: (context, _) => ListView(padding: const EdgeInsets.all(16), children: [
          Center(
            child: Ring(
              value: elapsed / total,
              color: C.calm,
              size: 200,
              width: 12,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(
                  result != null
                      ? '${result!.round()}'
                      : running
                          ? fmtDur(total - elapsed)
                          : '2:00',
                  style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800),
                ),
                Text(result != null ? 'ms RMSSD' : (running ? '${rr.length} uderzeń' : 'spokojnie, w leżeniu'),
                    style: TextStyle(color: C.muted)),
              ]),
            ),
          ),
          const SizedBox(height: 20),
          if (!hr.connected)
            const Text('Najpierw połącz opaskę na klatkę (np. Polar H10).',
                textAlign: TextAlign.center, style: TextStyle(color: C.bad))
          else if (!running && result == null)
            FilledButton(onPressed: _start, child: const Text('Rozpocznij pomiar'))
          else if (running)
            OutlinedButton(onPressed: _finish, child: const Text('Zakończ wcześniej'))
          else ...[
            if (result == null)
              const Text('Za mało czystych odstępów RR. Sprawdź, czy opaska dobrze przylega, i spróbuj ponownie.',
                  textAlign: TextAlign.center, style: TextStyle(color: C.bad))
            else
              Text('Tętno spoczynkowe ok. ${restHr ?? '–'}', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: _start, child: const Text('Powtórz'))),
              const SizedBox(width: 10),
              if (result != null) Expanded(child: FilledButton(onPressed: _save, child: const Text('Zapisz'))),
            ]),
          ],
          const SizedBox(height: 24),
          Text(
            'Mierz rano, zaraz po przebudzeniu, zawsze w tej samej pozycji. Trener porównuje wynik z Twoją normą z ostatnich '
            'tygodni — liczy się trend, nie pojedyncza liczba. Niższe HRV niż zwykle oznacza zwykle, że organizm '
            'jeszcze się regeneruje.',
            style: TextStyle(color: C.muted, height: 1.4),
          ),
          if (hist.isNotEmpty) ...[
            const SectionTitle('Ostatnie pomiary'),
            for (final h in hist.reversed.take(10))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${h.rmssd.round()} ms'),
                subtitle: Text('${fmtDate(h.at)}, ${fmtTime(h.at)}', style: TextStyle(color: C.muted)),
                trailing: Text(h.restHr > 0 ? '${h.restHr} bpm' : ''),
              ),
          ],
        ]),
      ),
    );
  }
}
