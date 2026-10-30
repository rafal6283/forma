import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/hr.dart';
import '../core/library.dart';
import '../core/models.dart';
import '../core/store.dart';
import '../core/trainer.dart';
import '../core/voice.dart';
import 'figure_view.dart';
import 'summary_screen.dart';
import 'theme.dart';
import 'widgets.dart';

enum _Kind { prep, work, rest }

class _Step {
  final _Kind kind;
  final int seconds;
  final PlanItem? item; // ćwiczenie (work) albo następne (prep/rest)
  _Step(this.kind, this.seconds, this.item);
}

/// Odtwarzacz treningu: animacja, odliczanie, głos, tętno na żywo.
class PlayerScreen extends StatefulWidget {
  final WorkoutPlan plan;
  const PlayerScreen({super.key, required this.plan});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final lib = Library.instance;
  final voice = Voice.instance;
  final hr = HrService.instance;
  late final List<_Step> steps;
  late final int totalPlanned = steps.fold(0, (a, s) => a + s.seconds);

  final _sw = Stopwatch();
  Timer? _timer;
  int idx = 0;
  int _stepStartMs = 0; // stan stopera na początku kroku
  int _lastWhole = -1;
  int _lastSampleSec = 0;
  bool paused = false;
  bool finished = false;
  final start = DateTime.now();

  final hrSec = <int>[]; // tętno co sekundę (0 = brak)
  final done = <DoneItem>[];
  double metSeconds = 0;

  @override
  void initState() {
    super.initState();
    final p = Store.instance.profile;
    voice.enabled = p.voice;
    voice.beeps = p.beeps;
    steps = [];
    final items = widget.plan.items;
    if (items.isNotEmpty) steps.add(_Step(_Kind.prep, 10, items.first));
    for (var i = 0; i < items.length; i++) {
      steps.add(_Step(_Kind.work, items[i].work, items[i]));
      if (items[i].rest > 0 && i < items.length - 1) steps.add(_Step(_Kind.rest, items[i].rest, items[i + 1]));
    }
    WakelockPlus.enable();
    if (p.hrDeviceId != null && hr.state == HrState.idle) hr.connectSaved(p.hrDeviceId!, p.hrDeviceName);
    _sw.start();
    _enter();
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    WakelockPlus.disable();
    voice.stop();
    super.dispose();
  }

  _Step get step => steps[idx];
  int get stepElapsedMs => _sw.elapsedMilliseconds - _stepStartMs;
  int get remaining => (step.seconds - stepElapsedMs / 1000).ceil().clamp(0, 9999);

  void _tick() {
    if (paused || finished) return;
    // próbki co sekundę całego treningu
    final sec = _sw.elapsedMilliseconds ~/ 1000;
    while (_lastSampleSec < sec) {
      _lastSampleSec++;
      hrSec.add(hr.freshBpm ?? 0);
      final e = step.item == null ? null : lib[step.item!.exId];
      metSeconds += step.kind == _Kind.work && e != null ? e.met : 2.0;
    }
    final rem = remaining;
    if (rem != _lastWhole) {
      _lastWhole = rem;
      if (rem <= 3 && rem > 0) voice.tick();
      if (step.kind == _Kind.work && step.seconds >= 40 && rem == step.seconds ~/ 2) {
        final e = lib[step.item!.exId];
        if (e != null && e.isStatic) voice.say('Połowa');
      }
    }
    if (stepElapsedMs >= step.seconds * 1000) {
      _next(auto: true);
    } else {
      setState(() {});
    }
  }

  void _recordWork() {
    if (step.kind != _Kind.work) return;
    final s = (stepElapsedMs / 1000).round();
    if (s >= 3) done.add(DoneItem(step.item!.exId, s.clamp(0, step.seconds), step.item!.side));
  }

  void _next({bool auto = false}) {
    _recordWork();
    if (idx >= steps.length - 1) {
      _finish(complete: true);
      return;
    }
    idx++;
    _stepStartMs = _sw.elapsedMilliseconds;
    _lastWhole = -1;
    _enter();
    setState(() {});
  }

  void _prev() {
    // w pierwszych 3 s kroku — poprzednie ćwiczenie, później od początku bieżącego
    if (stepElapsedMs > 3000 || idx == 0) {
      _stepStartMs = _sw.elapsedMilliseconds;
    } else {
      idx--;
      while (idx > 0 && steps[idx].kind != _Kind.work) {
        idx--;
      }
      _stepStartMs = _sw.elapsedMilliseconds;
    }
    _lastWhole = -1;
    _enter();
    setState(() {});
  }

  String _sideText(PlanItem it) => it.side == 1 ? ', prawa strona' : (it.side == 2 ? ', lewa strona' : '');

  void _enter() {
    final it = step.item;
    final e = it == null ? null : lib[it.exId];
    if (e == null) return;
    switch (step.kind) {
      case _Kind.prep:
        voice.say('Przygotuj się. ${phaseLabel[it!.phase]}. Pierwsze ćwiczenie: ${e.name}');
      case _Kind.rest:
        final roundStart = it!.round > 1 && _firstOfRound(it);
        voice.say(roundStart
            ? 'Przerwa. Runda ${it.round} z ${it.rounds}. Zaczynamy od: ${e.name}'
            : 'Przerwa. Następne: ${e.name}${_sideText(it)}');
      case _Kind.work:
        voice.go();
        final prevPhase = idx > 0 ? _prevWorkPhase() : null;
        final phaseNote = prevPhase != null && prevPhase != it!.phase ? '${phaseLabel[it.phase]}. ' : '';
        if (it!.side == 2 && idx > 0 && steps[idx - 1].item?.exId == it.exId) {
          voice.say('Zmiana strony');
        } else {
          voice.say('$phaseNote${e.name}${_sideText(it)}');
        }
    }
  }

  Phase? _prevWorkPhase() {
    for (var i = idx - 1; i >= 0; i--) {
      if (steps[i].kind == _Kind.work) return steps[i].item!.phase;
    }
    return null;
  }

  bool _firstOfRound(PlanItem it) {
    final items = widget.plan.items;
    final i = items.indexOf(it);
    return i > 0 && items[i - 1].round != it.round;
  }

  void _togglePause() {
    setState(() {
      paused = !paused;
      if (paused) {
        _sw.stop();
        voice.say('Pauza');
      } else {
        _sw.start();
      }
    });
  }

  Future<void> _finish({required bool complete}) async {
    if (finished) return;
    finished = true;
    _timer?.cancel();
    _sw.stop();
    voice.say(complete ? 'Koniec treningu. Świetna robota!' : 'Trening zakończony.');
    final p = Store.instance.profile;
    final valid = hrSec.where((b) => b > 0).toList();
    final avg = valid.isEmpty ? null : (valid.reduce((a, b) => a + b) / valid.length).round();
    final mx = valid.isEmpty ? null : valid.reduce((a, b) => a > b ? a : b);
    final zones = [0, 0, 0, 0, 0];
    for (final b in valid) {
      zones[Trainer.zone(b, p.maxHr) - 1]++;
    }
    // średnie co 5 s
    final hr5 = <int>[];
    for (var i = 0; i < hrSec.length; i += 5) {
      final chunk = hrSec.sublist(i, (i + 5).clamp(0, hrSec.length)).where((b) => b > 0).toList();
      hr5.add(chunk.isEmpty ? 0 : (chunk.reduce((a, b) => a + b) / chunk.length).round());
    }
    final end = DateTime.now();
    final seconds = _sw.elapsed.inSeconds;
    final session = Session(
      id: start.millisecondsSinceEpoch.toString(),
      start: start,
      end: end,
      kind: widget.plan.kind,
      title: widget.plan.title,
      done: done,
      kcal: Trainer.kcal(p: p, seconds: seconds, avgHr: valid.length > seconds * 0.6 ? avg : null, metSeconds: metSeconds),
      avgHr: avg,
      maxHr: mx,
      hr: hr5,
      zones: zones,
      readiness: widget.plan.readiness,
      plannedSeconds: widget.plan.items.fold(0, (a, i) => a + i.work),
    );
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => SummaryScreen(session: session)));
  }

  Future<bool> _confirmQuit() async {
    if (finished) return true;
    final wasPaused = paused;
    if (!paused) _togglePause();
    final r = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Przerwać trening?'),
        content: Text(done.isEmpty ? 'Nic jeszcze nie zostało zapisane.' : 'Możesz zapisać to, co już zrobione.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, 'back'), child: const Text('Wróć')),
          TextButton(onPressed: () => Navigator.pop(c, 'quit'), child: const Text('Wyjdź bez zapisu')),
          if (done.isNotEmpty) FilledButton(onPressed: () => Navigator.pop(c, 'save'), child: const Text('Zakończ i zapisz')),
        ],
      ),
    );
    if (r == 'save') {
      _recordWork();
      await _finish(complete: false);
      return false;
    }
    if (r == 'quit') return true;
    if (!wasPaused) _togglePause();
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final it = step.item;
    final e = it == null ? null : lib[it.exId];
    final work = step.kind == _Kind.work;
    final color = switch (step.kind) { _Kind.work => C.accent, _Kind.rest => C.calm, _Kind.prep => C.warn };
    final title = switch (step.kind) {
      _Kind.work => phaseLabel[it!.phase]!,
      _Kind.rest => 'Przerwa',
      _Kind.prep => 'Przygotuj się',
    };
    final elapsedAll = _sw.elapsedMilliseconds / 1000;
    final workIdx = steps.take(idx + 1).where((s) => s.kind == _Kind.work).length;
    final workTotal = steps.where((s) => s.kind == _Kind.work).length;
    final reps = work && e != null ? e.repsFor(step.seconds) : null;
    final tip = e != null && e.tips.isNotEmpty ? e.tips[(remaining ~/ 8) % e.tips.length] : null;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmQuit() && mounted) nav.pop();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
              child: Row(children: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () async {
                    final nav = Navigator.of(context);
                    if (await _confirmQuit() && mounted) nav.pop();
                  },
                ),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title.toUpperCase(),
                        style: TextStyle(color: color, fontWeight: FontWeight.w800, letterSpacing: 1.2, fontSize: 12)),
                    Text(
                      [
                        'Ćwiczenie $workIdx/$workTotal',
                        if (it != null && it.rounds > 1 && it.phase == Phase.main) 'runda ${it.round}/${it.rounds}',
                      ].join(' · '),
                      style: const TextStyle(color: C.muted, fontSize: 12),
                    ),
                  ]),
                ),
                const HrBadge(large: true),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: totalPlanned == 0 ? 0 : (elapsedAll / totalPlanned).clamp(0, 1).toDouble(),
                  minHeight: 5,
                  backgroundColor: C.surface2,
                  color: C.accent,
                ),
              ),
            ),
            Expanded(
              child: e == null
                  ? const SizedBox()
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Opacity(
                        opacity: work ? 1 : 0.55,
                        child: FigureView(e, playing: !paused),
                      ),
                    ),
            ),
            if (e != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(children: [
                  Text(
                    step.kind == _Kind.work ? e.name : 'Następne: ${e.name}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (it!.side == 1) 'prawa strona',
                      if (it.side == 2) 'lewa strona',
                      if (reps != null) 'ok. $reps powtórzeń',
                      if (e.isStatic) 'utrzymaj pozycję',
                    ].join(' · '),
                    style: const TextStyle(color: C.muted),
                  ),
                  if (tip != null) ...[
                    const SizedBox(height: 6),
                    Text(tip, textAlign: TextAlign.center, style: const TextStyle(color: C.text, fontSize: 15)),
                  ],
                ]),
              ),
            const SizedBox(height: 14),
            Ring(
              value: step.seconds == 0 ? 0 : 1 - (stepElapsedMs / 1000 / step.seconds).clamp(0, 1).toDouble(),
              color: color,
              size: 132,
              width: 10,
              child: Text(fmtDur(remaining), style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                IconButton.filledTonal(
                  iconSize: 28,
                  onPressed: _prev,
                  icon: const Icon(Icons.skip_previous),
                ),
                IconButton.filled(
                  iconSize: 44,
                  style: IconButton.styleFrom(backgroundColor: C.accent, padding: const EdgeInsets.all(14)),
                  onPressed: _togglePause,
                  icon: Icon(paused ? Icons.play_arrow : Icons.pause),
                ),
                IconButton.filledTonal(
                  iconSize: 28,
                  onPressed: () => _next(),
                  icon: const Icon(Icons.skip_next),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
