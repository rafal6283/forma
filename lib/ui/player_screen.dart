import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/coach.dart';
import '../core/hr.dart';
import '../core/library.dart';
import '../core/models.dart';
import '../core/store.dart';
import '../core/trainer.dart';
import '../core/voice.dart';
import '../core/voice_commands.dart';
import 'figure_view.dart';
import 'summary_screen.dart';
import 'theme.dart';
import 'widgets.dart';

enum _Kind { prep, work, rest, recover }

class _Step {
  final _Kind kind;
  int seconds;
  PlanItem? item; // ćwiczenie (work) albo następne (prep/rest)
  _Step(this.kind, this.seconds, this.item);
}

/// Strefy tętna, w których powinna odbywać się praca w danym formacie.
(int, int) targetZones(WorkoutFormat f) => switch (f) {
      WorkoutFormat.hiit || WorkoutFormat.tabata => (4, 5),
      WorkoutFormat.circuit || WorkoutFormat.strengthIntervals => (3, 4),
      WorkoutFormat.sets || WorkoutFormat.supersets => (2, 4),
      WorkoutFormat.flow => (1, 2),
    };

/// Odtwarzacz treningu: animacja, odliczanie, głos, tętno na żywo, komendy głosowe i tryb TV.
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
  final cmds = VoiceCommands.instance;
  final profile = Store.instance.profile;
  late final List<_Step> steps;
  late final int totalPlanned = steps.fold(0, (a, s) => a + s.seconds);

  final _sw = Stopwatch();
  Timer? _timer;
  int idx = 0;
  int _stepStartMs = 0;
  int _lastWhole = -1;
  int _lastSampleSec = 0;
  bool paused = false;
  bool finished = false;
  bool tv = false;
  bool listening = false;
  final start = DateTime.now();

  final hrSec = <int>[];
  final done = <DoneItem>[];
  final feedback = <String, int>{};
  double metSeconds = 0;

  // sterowanie tętnem
  int _aboveSec = 0, _belowSec = 0, _lastHrCue = -999, _restExtended = 0;
  int? _recoverStart, hrr;
  String? hrNote;

  @override
  void initState() {
    super.initState();
    voice.enabled = profile.voice;
    voice.beeps = profile.beeps;
    steps = [];
    final items = widget.plan.items;
    if (items.isNotEmpty) steps.add(_Step(_Kind.prep, 10, items.first));
    for (var i = 0; i < items.length; i++) {
      steps.add(_Step(_Kind.work, items[i].work, items[i]));
      if (items[i].rest > 0 && i < items.length - 1) steps.add(_Step(_Kind.rest, items[i].rest, items[i + 1]));
    }
    WakelockPlus.enable();
    if (profile.hrDeviceId != null && hr.state == HrState.idle) hr.connectSaved(profile.hrDeviceId!, profile.hrDeviceName);
    if (profile.voiceControl) _startListening();
    _sw.start();
    _enter();
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    WakelockPlus.disable();
    voice.stop();
    cmds.stop();
    if (tv) _setTv(false);
    super.dispose();
  }

  _Step get step => steps[idx];
  int get stepElapsedMs => _sw.elapsedMilliseconds - _stepStartMs;
  int get remaining => (step.seconds - stepElapsedMs / 1000).ceil().clamp(0, 9999);
  bool get repsStep => step.kind == _Kind.work && step.item?.reps != null;
  int repCount = 0;

  // ------------------------------------------------------------ komendy głosowe

  Future<void> _startListening() async {
    final ok = await cmds.start(_onCommand);
    if (mounted) setState(() => listening = ok);
    if (!ok && mounted) toast(context, cmds.error ?? 'Rozpoznawanie mowy niedostępne');
  }

  Future<void> _toggleListening() async {
    if (listening) {
      await cmds.stop();
      setState(() => listening = false);
    } else {
      await _startListening();
    }
  }

  void _onCommand(VoiceCmd c, int? value) {
    if (!mounted || finished) return;
    switch (c) {
      case VoiceCmd.next:
      case VoiceCmd.done:
        if (paused) _togglePause();
        _next();
      case VoiceCmd.pause:
        if (!paused) _togglePause();
      case VoiceCmd.resume:
        if (paused) _togglePause();
      case VoiceCmd.prev:
        _prev();
      case VoiceCmd.remaining:
        voice.say(repsStep ? 'Cel ${step.item!.reps} powtórzeń' : 'Zostało ${remaining} sekund');
      case VoiceCmd.setReps:
        if (repsStep && value != null) {
          setState(() => repCount = value);
          voice.say('$value');
        }
      case VoiceCmd.harder:
        _adjust(harder: true);
      case VoiceCmd.easier:
        _adjust(harder: false);
      case VoiceCmd.pain:
        _swapForPain();
    }
  }

  /// „Za trudne / za łatwe”: ocena ćwiczenia i zmiana pozostałych serii.
  void _adjust({required bool harder}) {
    final it = step.item;
    if (it == null) return;
    feedback[it.exId] = harder ? 1 : -1;
    for (var i = idx; i < steps.length; i++) {
      final s = steps[i];
      if (s.kind != _Kind.work || s.item?.exId != it.exId) continue;
      if (s.item!.reps != null) {
        s.item!.reps = (s.item!.reps! + (harder ? -2 : 2)).clamp(2, 40);
      } else if (i > idx) {
        s.seconds = (s.seconds * (harder ? 0.75 : 1.2)).round().clamp(10, 120);
      }
    }
    if (repsStep) repCount = step.item!.reps!;
    voice.say(harder ? 'Dobrze, odpuszczam w kolejnych seriach' : 'Dokładam w kolejnych seriach');
    setState(() {});
  }

  /// „Boli”: to ćwiczenie znika z treningu i zastępuje je łagodniejsze z tej samej partii.
  void _swapForPain() {
    final it = step.item;
    if (it == null) return;
    final cur = lib[it.exId];
    if (cur == null) return;
    final inPlan = steps.where((s) => s.item != null).map((s) => s.item!.exId).toSet();
    final alt = coach().alternative(cur, inPlan, seed: DateTime.now().millisecond);
    feedback[it.exId] = 1;
    if (alt == null || alt.lvl > cur.lvl) {
      voice.say('Pomijam to ćwiczenie');
      _next();
      return;
    }
    for (var i = idx; i < steps.length; i++) {
      final s = steps[i];
      if (s.item?.exId == it.exId) {
        s.item = PlanItem(
          exId: alt.id,
          work: s.item!.work,
          rest: s.item!.rest,
          phase: s.item!.phase,
          round: s.item!.round,
          rounds: s.item!.rounds,
          reps: s.item!.reps,
          tag: s.item!.tag,
        );
      }
    }
    voice.say('Zamieniam na: ${alt.name}');
    _stepStartMs = _sw.elapsedMilliseconds;
    setState(() {});
  }

  // ------------------------------------------------------------ zegar

  void _tick() {
    if (paused || finished) return;
    final sec = _sw.elapsedMilliseconds ~/ 1000;
    while (_lastSampleSec < sec) {
      _lastSampleSec++;
      final b = hr.freshBpm;
      hrSec.add(b ?? 0);
      final e = step.item == null ? null : lib[step.item!.exId];
      metSeconds += step.kind == _Kind.work && e != null ? e.met : 2.0;
      if (b != null && profile.hrControl) _hrControl(b, sec);
    }
    if (repsStep) {
      setState(() {});
      return;
    }
    final rem = remaining;
    if (rem != _lastWhole) {
      _lastWhole = rem;
      if (rem <= 3 && rem > 0 && step.kind != _Kind.recover) voice.tick();
      if (step.kind == _Kind.work && step.seconds >= 40 && rem == step.seconds ~/ 2) {
        final e = lib[step.item!.exId];
        if (e != null && e.isStatic) voice.say('Połowa');
      }
      // przerwa wg tętna: gdy tętno wciąż wysokie, dokładamy 10 s (maks. 3 razy)
      if (step.kind == _Kind.rest && rem == 3 && profile.hrControl && _restExtended < 3) {
        final b = hr.freshBpm;
        if (b != null && b > profile.maxHr * 0.8 && widget.plan.format != WorkoutFormat.tabata) {
          step.seconds += 10;
          _restExtended++;
          hrNote = 'Przerwa dłuższa: tętno $b';
          voice.say('Tętno jeszcze wysokie. Dodaję 10 sekund.');
        }
      }
    }
    if (stepElapsedMs >= step.seconds * 1000) {
      _next(auto: true);
    } else {
      setState(() {});
    }
  }

  /// Podpowiedzi w trakcie pracy: za wysoko → zwolnij, za nisko w HIIT → mocniej.
  void _hrControl(int bpm, int sec) {
    if (step.kind != _Kind.work || step.item?.phase != Phase.main) {
      _aboveSec = 0;
      _belowSec = 0;
      return;
    }
    final z = Trainer.zone(bpm, profile.maxHr);
    final (lo, hi) = targetZones(widget.plan.format);
    _aboveSec = z > hi || z == 5 && hi < 5 ? _aboveSec + 1 : 0;
    _belowSec = z < lo ? _belowSec + 1 : 0;
    if (sec - _lastHrCue < 45) return;
    if (_aboveSec >= 15) {
      _lastHrCue = sec;
      hrNote = 'Tętno wysoko (strefa $z)';
      voice.say('Tętno wysokie. Zwolnij i spokojnie oddychaj.');
    } else if (_belowSec >= 20 && lo >= 4) {
      _lastHrCue = sec;
      hrNote = 'Za nisko jak na ${formatLabel[widget.plan.format]}';
      voice.say('Mocniej! Podkręć tempo.');
    }
  }

  void _recordWork() {
    if (step.kind != _Kind.work) return;
    final s = (stepElapsedMs / 1000).round();
    final it = step.item!;
    if (it.reps != null) {
      if (repCount > 0) done.add(DoneItem(it.exId, s.clamp(1, 600), it.side, reps: repCount, target: it.reps));
      return;
    }
    if (s >= 3) done.add(DoneItem(it.exId, s.clamp(0, step.seconds), it.side));
  }

  void _next({bool auto = false}) {
    if (step.kind == _Kind.recover) {
      _endRecovery();
      return;
    }
    _recordWork();
    if (idx >= steps.length - 1) {
      // minuta pomiaru regeneracji tętna, gdy jest opaska
      final b = hr.freshBpm;
      if (profile.hrControl && b != null && auto) {
        steps.add(_Step(_Kind.recover, 60, null));
        _recoverStart = _recentPeak();
        idx++;
        _stepStartMs = _sw.elapsedMilliseconds;
        voice.say('Koniec treningu. Teraz minuta spokoju — mierzę, jak szybko spada tętno.');
        setState(() {});
        return;
      }
      _finish(complete: true);
      return;
    }
    idx++;
    _stepStartMs = _sw.elapsedMilliseconds;
    _lastWhole = -1;
    _restExtended = 0;
    _enter();
    setState(() {});
  }

  int? _recentPeak() {
    final last = hrSec.length > 10 ? hrSec.sublist(hrSec.length - 10) : hrSec;
    final v = last.where((b) => b > 0);
    return v.isEmpty ? hr.freshBpm : v.reduce((a, b) => a > b ? a : b);
  }

  void _endRecovery() {
    final end = hr.freshBpm;
    if (_recoverStart != null && end != null) hrr = (_recoverStart! - end).clamp(0, 120);
    if (hrr != null) voice.say('Tętno spadło o $hrr uderzeń.');
    _finish(complete: true, spoken: true);
  }

  void _prev() {
    if (step.kind == _Kind.recover) return;
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
    hrNote = null;
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
        repCount = it!.reps ?? 0;
        final prevPhase = idx > 0 ? _prevWorkPhase() : null;
        final phaseNote = prevPhase != null && prevPhase != it.phase ? '${phaseLabel[it.phase]}. ' : '';
        final repsNote = it.reps != null ? '. ${it.reps} powtórzeń' : '';
        if (it.side == 2 && idx > 0 && steps[idx - 1].item?.exId == it.exId) {
          voice.say('Zmiana strony$repsNote');
        } else {
          voice.say('$phaseNote${e.name}${_sideText(it)}$repsNote');
        }
      case _Kind.recover:
        break;
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

  // ------------------------------------------------------------ tryb TV

  Future<void> _setTv(bool on) async {
    if (on) {
      await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      await SystemChrome.setPreferredOrientations([]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  Future<void> _toggleTv() async {
    tv = !tv;
    await _setTv(tv);
    if (mounted) setState(() {});
  }

  // ------------------------------------------------------------ koniec

  Future<void> _finish({required bool complete, bool spoken = false}) async {
    if (finished) return;
    finished = true;
    _timer?.cancel();
    _sw.stop();
    await cmds.stop();
    if (tv) await _setTv(false);
    if (!spoken) voice.say(complete ? 'Koniec treningu. Świetna robota!' : 'Trening zakończony.');
    final p = profile;
    final valid = hrSec.where((b) => b > 0).toList();
    final avg = valid.isEmpty ? null : (valid.reduce((a, b) => a + b) / valid.length).round();
    final mx = valid.isEmpty ? null : valid.reduce((a, b) => a > b ? a : b);
    final zones = [0, 0, 0, 0, 0];
    for (final b in valid) {
      zones[Trainer.zone(b, p.maxHr) - 1]++;
    }
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
      format: widget.plan.format,
      programDay: widget.plan.programDay,
      challenge: widget.plan.challenge,
      hrr: hrr,
      feedback: {...feedback},
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

  // ------------------------------------------------------------ widok

  @override
  Widget build(BuildContext context) {
    final it = step.item;
    final e = it == null ? null : lib[it.exId];
    final work = step.kind == _Kind.work;
    final color = switch (step.kind) {
      _Kind.work => C.accent,
      _Kind.rest => C.calm,
      _Kind.prep => C.warn,
      _Kind.recover => C.good,
    };
    final title = switch (step.kind) {
      _Kind.work => phaseLabel[it!.phase]!,
      _Kind.rest => 'Przerwa',
      _Kind.prep => 'Przygotuj się',
      _Kind.recover => 'Regeneracja tętna',
    };
    final elapsedAll = _sw.elapsedMilliseconds / 1000;
    final workIdx = steps.take(idx + 1).where((s) => s.kind == _Kind.work).length;
    final workTotal = steps.where((s) => s.kind == _Kind.work).length;
    final approx = work && e != null && it?.reps == null ? e.repsFor(step.seconds) : null;
    final tip = e != null && e.tips.isNotEmpty ? e.tips[(remaining ~/ 8) % e.tips.length] : null;
    final land = MediaQuery.of(context).orientation == Orientation.landscape;
    final big = land ? MediaQuery.of(context).size.height / 400 : 1.0;

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
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
                style: TextStyle(color: color, fontWeight: FontWeight.w800, letterSpacing: 1.2, fontSize: 12 * big)),
            Text(
              [
                if (step.kind != _Kind.recover) 'Ćwiczenie $workIdx/$workTotal',
                if (it != null && it.rounds > 1 && it.phase == Phase.main) 'runda ${it.round}/${it.rounds}',
                if (hrNote != null) hrNote!,
              ].join(' · '),
              style: TextStyle(color: hrNote != null ? C.warn : C.muted, fontSize: 12 * big),
            ),
          ]),
        ),
        IconButton(
          tooltip: 'Sterowanie głosem',
          onPressed: _toggleListening,
          icon: ListenableBuilder(
            listenable: cmds,
            builder: (_, __) => Icon(
              listening ? (cmds.listening ? Icons.mic : Icons.mic_none) : Icons.mic_off,
              color: listening ? (cmds.listening ? C.good : C.text) : C.muted,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Tryb TV',
          onPressed: _toggleTv,
          icon: Icon(tv ? Icons.stay_current_portrait : Icons.tv),
        ),
        const HrBadge(large: true),
      ]),
    );

    final progress = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: totalPlanned == 0 ? 0 : (elapsedAll / totalPlanned).clamp(0, 1).toDouble(),
          minHeight: 5,
          backgroundColor: C.surface2,
          color: C.accent,
        ),
      ),
    );

    final figure = step.kind == _Kind.recover
        ? Center(child: Icon(Icons.self_improvement, size: 140 * big, color: C.good))
        : e == null
            ? const SizedBox()
            : Opacity(opacity: work ? 1 : 0.55, child: FigureView(e, playing: !paused));

    final info = step.kind == _Kind.recover
        ? Text('Stań lub usiądź spokojnie.\nTętno na końcu pracy: ${_recoverStart ?? '–'}',
            textAlign: TextAlign.center, style: TextStyle(color: C.muted, fontSize: 15 * big))
        : e == null
            ? const SizedBox()
            : Column(children: [
                Text(
                  work ? e.name : 'Następne: ${e.name}',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 24 * big, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if (it!.tag != null) it.tag!,
                    if (it.side == 1) 'prawa strona',
                    if (it.side == 2) 'lewa strona',
                    if (approx != null) 'ok. $approx powtórzeń',
                    if (it.reps != null && !work) '${it.reps} powtórzeń',
                    if (e.isStatic) 'utrzymaj pozycję',
                  ].join(' · '),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: C.muted, fontSize: 14 * big),
                ),
                if (tip != null) ...[
                  const SizedBox(height: 6),
                  Text(tip, textAlign: TextAlign.center, style: TextStyle(color: C.text, fontSize: 15 * big)),
                ],
                if (listening && cmds.lastHeard.isNotEmpty && !land) ...[
                  const SizedBox(height: 4),
                  Text('„${cmds.lastHeard}”', style: const TextStyle(color: C.muted, fontSize: 11, fontStyle: FontStyle.italic)),
                ],
              ]);

    final clock = repsStep
        ? _RepsCounter(
            count: repCount,
            target: it!.reps!,
            elapsed: stepElapsedMs ~/ 1000,
            scale: big,
            onChange: (v) => setState(() => repCount = v.clamp(0, 99)),
            onDone: () => _next(),
          )
        : Ring(
            value: step.seconds == 0 ? 0 : 1 - (stepElapsedMs / 1000 / step.seconds).clamp(0, 1).toDouble(),
            color: color,
            size: 132 * big,
            width: 10 * big,
            child: Text(fmtDur(remaining), style: TextStyle(fontSize: 34 * big, fontWeight: FontWeight.w800)),
          );

    final controls = Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
      IconButton.filledTonal(iconSize: 28, onPressed: _prev, icon: const Icon(Icons.skip_previous)),
      IconButton.filled(
        iconSize: 44,
        style: IconButton.styleFrom(backgroundColor: C.accent, padding: const EdgeInsets.all(14)),
        onPressed: _togglePause,
        icon: Icon(paused ? Icons.play_arrow : Icons.pause),
      ),
      IconButton.filledTonal(iconSize: 28, onPressed: () => _next(), icon: const Icon(Icons.skip_next)),
    ]);

    final body = land
        ? Column(children: [
            header,
            progress,
            Expanded(
              child: Row(children: [
                Expanded(flex: 3, child: Padding(padding: const EdgeInsets.all(12), child: figure)),
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 20, 8),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      info,
                      SizedBox(height: 12 * big),
                      clock,
                      SizedBox(height: 10 * big),
                      controls,
                    ]),
                  ),
                ),
              ]),
            ),
          ])
        : Column(children: [
            header,
            progress,
            Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: figure)),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: info),
            const SizedBox(height: 14),
            clock,
            const SizedBox(height: 10),
            Padding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 16), child: controls),
          ]);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmQuit() && mounted) nav.pop();
      },
      child: Scaffold(body: SafeArea(child: body)),
    );
  }
}

/// Licznik powtórzeń w serii: cel, korekta −/+ i „Gotowe”.
class _RepsCounter extends StatelessWidget {
  final int count, target, elapsed;
  final double scale;
  final ValueChanged<int> onChange;
  final VoidCallback onDone;
  const _RepsCounter({
    required this.count,
    required this.target,
    required this.elapsed,
    required this.onChange,
    required this.onDone,
    this.scale = 1,
  });

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton.filledTonal(onPressed: () => onChange(count - 1), icon: const Icon(Icons.remove)),
          SizedBox(
            width: 120 * scale,
            child: Column(children: [
              Text('$count',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 52 * scale, fontWeight: FontWeight.w800, color: count >= target ? C.good : C.text)),
              Text('cel $target · ${fmtDur(elapsed)}', style: const TextStyle(color: C.muted, fontSize: 12)),
            ]),
          ),
          IconButton.filledTonal(onPressed: () => onChange(count + 1), icon: const Icon(Icons.add)),
        ]),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: onDone,
          icon: const Icon(Icons.check),
          label: const Text('Seria zrobiona'),
          style: FilledButton.styleFrom(minimumSize: const Size(220, 52)),
        ),
      ]);
}
