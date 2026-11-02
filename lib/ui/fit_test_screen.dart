import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/hr.dart';
import '../core/library.dart';
import '../core/models.dart';
import '../core/store.dart';
import '../core/voice.dart';
import 'figure_view.dart';
import 'theme.dart';
import 'widgets.dart';

enum _Stage { intro, restHr, pushups, squats, plank, hrrWork, hrrRest, result }

/// Test formy: pompki i przysiady na minutę, deska do upadku, tętno spoczynkowe i regeneracja tętna.
class FitTestScreen extends StatefulWidget {
  const FitTestScreen({super.key});

  @override
  State<FitTestScreen> createState() => _FitTestScreenState();
}

class _FitTestScreenState extends State<FitTestScreen> {
  final hr = HrService.instance;
  final voice = Voice.instance;
  _Stage stage = _Stage.intro;
  Timer? _timer;
  int secs = 0; // upływ czasu w etapie
  bool running = false;
  int count = 0;
  int? pushups, squats, plank, restHr, hrr;
  final _bpms = <int>[];
  int? _peak;

  bool get strap => hr.connected;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    final p = Store.instance.profile;
    if (p.hrDeviceId != null && hr.state == HrState.idle) hr.connectSaved(p.hrDeviceId!, p.hrDeviceName);
  }

  @override
  void dispose() {
    _timer?.cancel();
    WakelockPlus.disable();
    voice.stop();
    super.dispose();
  }

  int get _limit => switch (stage) {
        _Stage.restHr => 30,
        _Stage.pushups || _Stage.squats || _Stage.hrrWork || _Stage.hrrRest => 60,
        _ => 0,
      };

  void _go(_Stage s) {
    _timer?.cancel();
    setState(() {
      stage = s;
      secs = 0;
      count = 0;
      running = false;
      _bpms.clear();
    });
    switch (s) {
      case _Stage.restHr:
        voice.say('Usiądź wygodnie i oddychaj spokojnie. Mierzę tętno spoczynkowe.');
        _run();
      case _Stage.pushups:
        voice.say('Pompki. Jak najwięcej przez minutę. Dotykaj ekranu przy każdej pompce albo wpisz wynik na końcu.');
      case _Stage.squats:
        voice.say('Przysiady. Jak najwięcej przez minutę.');
      case _Stage.plank:
        voice.say('Deska na przedramionach. Trzymaj, ile dasz radę, a potem dotknij stop.');
      case _Stage.hrrWork:
        voice.say('Minuta pajacyków albo marszu w miejscu w dobrym tempie. Potem zmierzę, jak szybko spada tętno.');
      case _Stage.hrrRest:
        _peak = hr.freshBpm;
        voice.say('Stop. Stań spokojnie przez minutę.');
        _run();
      default:
        break;
    }
  }

  void _run() {
    running = true;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => secs++);
      final b = hr.freshBpm;
      if (b != null) _bpms.add(b);
      final lim = _limit;
      if (lim > 0) {
        final rem = lim - secs;
        if (rem <= 3 && rem > 0) voice.tick();
        if (rem == 30 && stage != _Stage.restHr) voice.say('Połowa');
        if (rem <= 0) _stageDone();
      }
    });
    setState(() {});
  }

  void _stageDone() {
    _timer?.cancel();
    running = false;
    switch (stage) {
      case _Stage.restHr:
        if (_bpms.isNotEmpty) {
          final s = [..._bpms]..sort();
          restHr = s[s.length ~/ 3]; // niższa część pomiaru
        }
        _go(_Stage.pushups);
      case _Stage.pushups:
        voice.say('Koniec. Popraw wynik, jeśli trzeba.');
        setState(() {});
      case _Stage.squats:
        voice.say('Koniec. Popraw wynik, jeśli trzeba.');
        setState(() {});
      case _Stage.hrrWork:
        _go(_Stage.hrrRest);
      case _Stage.hrrRest:
        final end = hr.freshBpm;
        if (_peak != null && end != null) hrr = (_peak! - end).clamp(0, 120);
        _finish();
      default:
        break;
    }
  }

  void _finish() {
    voice.say('Test skończony.');
    setState(() => stage = _Stage.result);
  }

  Widget _timerBig() {
    final lim = _limit;
    final shown = lim > 0 ? (lim - secs).clamp(0, lim) : secs;
    return Ring(
      value: lim > 0 ? (secs / lim).clamp(0, 1).toDouble() : 0,
      color: C.accent,
      size: 150,
      width: 10,
      child: Text(fmtDur(shown), style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800)),
    );
  }

  Widget _counterStage(String exId, String title, void Function(int) save, _Stage next) {
    final e = Library.instance[exId];
    final ended = !running && secs >= 60;
    return Column(children: [
      if (e != null) SizedBox(height: 160, child: FigureView(e, playing: running)),
      Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
      const SizedBox(height: 12),
      _timerBig(),
      const SizedBox(height: 12),
      GestureDetector(
        onTap: running ? () => setState(() => count++) : null,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(20)),
          child: Column(children: [
            Text('$count', style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w800)),
            Text(running ? 'dotknij przy każdym powtórzeniu' : 'powtórzeń', style: TextStyle(color: C.muted)),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton.filledTonal(onPressed: () => setState(() => count = (count - 1).clamp(0, 999)), icon: const Icon(Icons.remove)),
        const SizedBox(width: 16),
        IconButton.filledTonal(onPressed: () => setState(() => count++), icon: const Icon(Icons.add)),
      ]),
      const SizedBox(height: 16),
      if (!running && !ended)
        FilledButton(onPressed: _run, style: _btn, child: const Text('Start (1 minuta)'))
      else if (ended)
        FilledButton(
          onPressed: () {
            save(count);
            _go(next);
          },
          style: _btn,
          child: const Text('Zapisz i dalej'),
        ),
      TextButton(onPressed: () => _go(next), child: const Text('Pomiń ten test')),
    ]);
  }

  static final _btn = FilledButton.styleFrom(minimumSize: const Size.fromHeight(54));

  @override
  Widget build(BuildContext context) {
    final prev = Store.instance.tests.isEmpty ? null : Store.instance.tests.last;
    return Scaffold(
      appBar: AppBar(title: const Text('Test formy'), actions: const [Padding(padding: EdgeInsets.only(right: 12), child: HrBadge())]),
      body: ListenableBuilder(
        listenable: hr,
        builder: (context, _) => ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
          switch (stage) {
            _Stage.intro => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('Sprawdź, gdzie jesteś', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(
                  'Ok. 10 minut. Rozgrzej się wcześniej 3–5 minut.\n\n'
                  '1. Tętno spoczynkowe (30 s)${strap ? '' : ' — wymaga opaski'}\n'
                  '2. Pompki przez minutę (mogą być na kolanach — rób zawsze tak samo)\n'
                  '3. Przysiady przez minutę\n'
                  '4. Deska na przedramionach do upadku\n'
                  '5. Regeneracja tętna: minuta pracy i minuta odpoczynku${strap ? '' : ' — wymaga opaski'}\n\n'
                  'Powtarzaj co 4 tygodnie. Wynik 0–100 pokazuje postęp względem Ciebie samego.',
                  style: TextStyle(color: C.muted, height: 1.45),
                ),
                if (prev != null) ...[
                  const SizedBox(height: 10),
                  Text('Ostatni test: ${fmtDate(prev.at)} — wynik ${prev.score}', style: const TextStyle(color: C.accent)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => _go(strap ? _Stage.restHr : _Stage.pushups),
                  style: _btn,
                  child: const Text('Zaczynamy'),
                ),
              ]),
            _Stage.restHr => Column(children: [
                const Text('Tętno spoczynkowe', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 16),
                _timerBig(),
                const SizedBox(height: 12),
                Text('Siedź spokojnie, nie rozmawiaj.', style: TextStyle(color: C.muted)),
              ]),
            _Stage.pushups => _counterStage('pushups', 'Pompki — 1 minuta', (v) => pushups = v, _Stage.squats),
            _Stage.squats => _counterStage('squat', 'Przysiady — 1 minuta', (v) => squats = v, _Stage.plank),
            _Stage.plank => Column(children: [
                if (Library.instance['plank'] != null)
                  SizedBox(height: 160, child: FigureView(Library.instance['plank']!, playing: running)),
                const Text('Deska do upadku', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                _timerBig(),
                const SizedBox(height: 16),
                if (!running && secs == 0)
                  FilledButton(onPressed: _run, style: _btn, child: const Text('Start'))
                else if (running)
                  FilledButton(
                    onPressed: () {
                      _timer?.cancel();
                      setState(() {
                        running = false;
                        plank = secs;
                      });
                      voice.say('$secs sekund');
                    },
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54), backgroundColor: C.bad),
                    child: const Text('Stop'),
                  )
                else
                  FilledButton(
                    onPressed: () => strap ? _go(_Stage.hrrWork) : _finish(),
                    style: _btn,
                    child: const Text('Dalej'),
                  ),
                TextButton(onPressed: () => strap ? _go(_Stage.hrrWork) : _finish(), child: const Text('Pomiń')),
              ]),
            _Stage.hrrWork || _Stage.hrrRest => Column(children: [
                if (stage == _Stage.hrrWork && Library.instance['jumping_jacks'] != null)
                  SizedBox(
                    height: 160,
                    child: FigureView(
                      Library.instance[Store.instance.profile.noJumping ? 'march' : 'jumping_jacks']!,
                      playing: running,
                    ),
                  ),
                Text(stage == _Stage.hrrWork ? 'Minuta pracy' : 'Minuta odpoczynku',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                _timerBig(),
                const SizedBox(height: 12),
                if (stage == _Stage.hrrWork && !running)
                  FilledButton(onPressed: _run, style: _btn, child: const Text('Start'))
                else
                  Text(stage == _Stage.hrrRest && _peak != null ? 'Tętno na koniec pracy: $_peak' : '',
                      style: TextStyle(color: C.muted)),
                TextButton(onPressed: _finish, child: const Text('Pomiń')),
              ]),
            _Stage.result => _result(prev),
          },
        ]),
      ),
    );
  }

  Widget _result(FitTest? prev) {
    final t = FitTest(DateTime.now(), pushups: pushups, squats: squats, plank: plank, restHr: restHr, hrr: hrr);
    final p = Store.instance.profile;
    final suggested = (1 + t.score / 25).clamp(1.0, 5.0);
    final pp = prev?.parts ?? const {};
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Center(
        child: Ring(
          value: t.score / 100,
          color: C.readiness(t.score),
          size: 170,
          width: 12,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${t.score}', style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w800)),
            Text(prev == null ? 'wynik formy' : '${t.score >= prev.score ? '+' : ''}${t.score - prev.score} od ostatniego',
                style: TextStyle(color: C.muted)),
          ]),
        ),
      ),
      const SizedBox(height: 16),
      Card(
        child: Column(children: [
          for (final e in t.parts.entries)
            ListTile(
              dense: true,
              title: Text(e.key),
              subtitle: Text(
                switch (e.key) {
                  'Pompki' => '$pushups w minutę',
                  'Przysiady' => '$squats w minutę',
                  'Deska' => fmtDur(plank ?? 0),
                  'Tętno spoczynkowe' => '$restHr bpm',
                  _ => 'spadek o $hrr bpm w minutę',
                },
                style: TextStyle(color: C.muted),
              ),
              trailing: Text(
                '${e.value}${pp[e.key] != null ? ' (${e.value - pp[e.key]! >= 0 ? '+' : ''}${e.value - pp[e.key]!})' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 12),
      if ((suggested - p.level).abs() >= 0.5)
        Text(
          'Wynik odpowiada poziomowi ${suggested.toStringAsFixed(1).replaceAll('.', ',')} — teraz masz ${p.level.toStringAsFixed(1).replaceAll('.', ',')}.',
          style: TextStyle(color: C.muted),
        ),
      const SizedBox(height: 12),
      FilledButton(
        style: _btn,
        onPressed: t.parts.isEmpty
            ? null
            : () async {
                await Store.instance.addTest(t);
                if (mounted) Navigator.pop(context);
              },
        child: const Text('Zapisz wynik'),
      ),
      if ((suggested - p.level).abs() >= 0.5)
        OutlinedButton(
          onPressed: t.parts.isEmpty
              ? null
              : () async {
                  p.level = (suggested * 10).round() / 10;
                  await Store.instance.addTest(t);
                  if (mounted) Navigator.pop(context);
                },
          child: const Text('Zapisz i ustaw ten poziom'),
        ),
    ]);
  }
}
