import 'dart:io';

import 'package:flutter/material.dart';

import '../core/coach.dart';
import '../core/health_sync.dart';
import '../core/library.dart';
import '../core/models.dart';
import '../core/store.dart';
import '../core/strava.dart';
import 'muscle_map.dart';
import 'session_widgets.dart';
import 'theme.dart';
import 'widgets.dart';

/// Po treningu: wynik, ocena trudności (RPE) i ćwiczeń — trener uczy się z tych ocen.
class SummaryScreen extends StatefulWidget {
  final Session session;
  const SummaryScreen({super.key, required this.session});

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  late final Session s = widget.session;
  bool saving = false;

  static const rpeText = {
    1: 'Bardzo lekko',
    2: 'Lekko',
    3: 'Lekko',
    4: 'Umiarkowanie',
    5: 'Umiarkowanie',
    6: 'Dość ciężko',
    7: 'Ciężko',
    8: 'Bardzo ciężko',
    9: 'Prawie maksimum',
    10: 'Maksimum',
  };

  Future<void> _save() async {
    setState(() => saving = true);
    final store = Store.instance;
    final before = store.profile.level;
    final next = coach().nextLevel(s);
    store.profile.level = next;
    for (final f in s.feedback.entries) {
      store.stat(f.key).score += f.value;
    }
    await store.addSession(s);
    var msg = 'Zapisano trening';
    if (store.profile.healthConnect) {
      final ok = await HealthSync.instance.writeSession(s);
      if (ok) {
        s.inHealth = true;
        await store.save();
        msg += ' i wysłano do ${Platform.isIOS ? 'Zdrowia' : 'Health Connect'}';
      } else {
        msg += ' (Health Connect: ${HealthSync.instance.lastError ?? 'błąd'})';
      }
    }
    final diff = next - before;
    if (diff.abs() >= 0.05) {
      msg += diff > 0 ? '. Następnym razem trochę mocniej.' : '. Następnym razem trochę lżej.';
    }
    if (!mounted) return;
    toast(context, msg);
    Navigator.pop(context);
    // Strava w tle — wynik w historii treningu
    if (store.profile.stravaAuto && await Strava.instance.connected()) {
      try {
        await Strava.instance.push(s);
      } catch (e) {
        debugPrint('Strava: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lib = Library.instance;
    final mainIds = <String>[];
    for (final d in s.done) {
      final e = lib[d.exId];
      if (e == null || e.type == ExType.stretch || e.type == ExType.warmup) continue;
      if (!mainIds.contains(d.exId)) mainIds.add(d.exId);
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await confirm(context, 'Odrzucić trening?', 'Ten trening nie zostanie zapisany.', ok: 'Odrzuć')) nav.pop();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(s.completion > 0.95 ? 'Brawo! 💪' : 'Podsumowanie'), automaticallyImplyLeading: false),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
          children: [
            Text(s.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            Text('${(s.completion * 100).round()}% planu', style: const TextStyle(color: C.muted)),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SessionStats(s),
                  if (s.hrr != null) ...[
                    const SizedBox(height: 10),
                    Text('Regeneracja: tętno spadło o ${s.hrr} uderzeń w minutę${s.hrr! >= 25 ? ' — bardzo dobrze' : s.hrr! >= 12 ? '' : ' — organizm jest zmęczony'}',
                        style: const TextStyle(color: C.good)),
                  ],
                  if (muscleLoad(s.done).isNotEmpty) ...[
                    const SizedBox(height: 16),
                    MuscleMap(muscleLoad(s.done), height: 220),
                  ],
                  if (s.hr.where((v) => v > 0).length > 2) ...[
                    const SizedBox(height: 16),
                    HrChart(s),
                    const SizedBox(height: 10),
                    ZonesBar(s.zones),
                  ],
                ]),
              ),
            ),
            const SectionTitle('Jak było?'),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text('${s.rpe}', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: C.accent)),
                    const SizedBox(width: 12),
                    Text(rpeText[s.rpe]!, style: const TextStyle(fontSize: 18)),
                  ]),
                  Slider(
                    value: s.rpe.toDouble(),
                    min: 1,
                    max: 10,
                    divisions: 9,
                    onChanged: (v) => setState(() => s.rpe = v.round()),
                  ),
                  const Text('Trener celuje w „ciężko” (7). Lżej — podniesie poprzeczkę, ciężej — odpuści.',
                      style: TextStyle(color: C.muted, fontSize: 12)),
                ]),
              ),
            ),
            if (mainIds.isNotEmpty) ...[
              const SectionTitle('Ćwiczenia'),
              Card(
                child: Column(children: [
                  for (final id in mainIds)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                      child: Row(children: [
                        Expanded(child: Text(lib[id]!.name)),
                        SegmentedButton<int>(
                          showSelectedIcon: false,
                          style: const ButtonStyle(visualDensity: VisualDensity.compact),
                          segments: const [
                            ButtonSegment(value: -1, label: Text('łatwe')),
                            ButtonSegment(value: 0, label: Text('ok')),
                            ButtonSegment(value: 1, label: Text('trudne')),
                          ],
                          selected: {s.feedback[id] ?? 0},
                          onSelectionChanged: (v) => setState(() {
                            if (v.first == 0) {
                              s.feedback.remove(id);
                            } else {
                              s.feedback[id] = v.first;
                            }
                          }),
                        ),
                      ]),
                    ),
                ]),
              ),
            ],
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              onPressed: saving ? null : _save,
              child: Text(saving ? 'Zapisuję…' : 'Zapisz trening'),
            ),
          ),
        ),
      ),
    );
  }
}
