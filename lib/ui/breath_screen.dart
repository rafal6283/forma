import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/hr.dart';
import '../core/models.dart';
import '../core/ppg.dart';
import '../core/sfx.dart';
import '../core/store.dart';
import 'insights.dart';
import 'ppg_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// RMSSD z listy odstępów RR (ms), z odrzuceniem artefaktów (> 25% od mediany).
double? rmssdOf(List<double> rr) {
  if (rr.length < 10) return null;
  final s = [...rr]..sort();
  final med = s[s.length ~/ 2];
  final ok = [for (final r in rr) (r - med).abs() <= 0.25 * med];
  var sum = 0.0, n = 0;
  for (var i = 1; i < rr.length; i++) {
    if (ok[i] && ok[i - 1]) {
      final d = rr[i] - rr[i - 1];
      sum += d * d;
      n++;
    }
  }
  return n < 8 ? null : math.sqrt(sum / n);
}

/// Oddychanie z biofeedbackiem: rytm ~6 oddechów/min, tętno na żywo (pasek lub palec na aparacie), HRV przed i po.
class BreathScreen extends StatefulWidget {
  const BreathScreen({super.key});

  @override
  State<BreathScreen> createState() => _BreathScreenState();
}

class _BreathScreenState extends State<BreathScreen> with SingleTickerProviderStateMixin {
  static const paces = [(5.0, 5.0, '6/min'), (4.0, 6.0, 'spokojnie 4–6'), (4.0, 4.0, 'kwadrat 4–4')];
  int pace = 0, minutes = 5;
  bool running = false, finished = false, useCamera = false;
  final sw = Stopwatch();
  Timer? timer;
  late final AnimationController anim = AnimationController(vsync: this, duration: const Duration(seconds: 1));
  final rr = <(double, double)>[]; // (czas s, RR ms)
  final hrLine = <double>[];
  StreamSubscription<double>? _rrSub;
  int _lastPhase = -1;
  double? before, after;

  // aparat (gdy brak paska)
  CameraController? cam;
  final pt = <double>[], pv = <double>[];
  final camClock = Stopwatch();
  int _beatsUsed = 0;

  HrService get hr => HrService.instance;
  bool get strap => hr.freshBpm != null;

  @override
  void dispose() {
    timer?.cancel();
    _rrSub?.cancel();
    anim.dispose();
    _stopCam();
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _stopCam() async {
    final c = cam;
    cam = null;
    if (c == null) return;
    try {
      if (c.value.isStreamingImages) await c.stopImageStream();
      await c.setFlashMode(FlashMode.off);
    } catch (_) {}
    await c.dispose();
  }

  Future<void> _startCam() async {
    try {
      final cams = await availableCameras();
      final back = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cams.first);
      final c = CameraController(back, ResolutionPreset.low,
          enableAudio: false, imageFormatGroup: Platform.isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.nv21);
      await c.initialize();
      await c.setFlashMode(FlashMode.torch);
      cam = c;
      camClock
        ..reset()
        ..start();
      await c.startImageStream((img) {
        final (m, sd) = frameStats(img);
        if (m > 25 && sd < 28) {
          pt.add(camClock.elapsedMicroseconds / 1000);
          pv.add(m);
        }
      });
    } catch (e) {
      if (mounted) toast(context, 'Aparat niedostępny: $e');
    }
  }

  /// Nowe uderzenia z aparatu (co sekundę analizujemy ostatnie 20 s).
  void _camBeats() {
    if (pt.length < 120) return;
    final from = math.max(0, pt.length - 600);
    final b = Ppg.beats(pt.sublist(from), pv.sublist(from));
    if (b.length < 3) return;
    // dopisujemy tylko odstępy po ostatnio użytym uderzeniu
    for (var i = 1; i < b.length; i++) {
      if (b[i] <= _beatsUsed) continue;
      final r = b[i] - b[i - 1];
      if (r > 333 && r < 1500) {
        rr.add((sw.elapsedMilliseconds / 1000, r));
        hrLine.add(60000 / r);
      }
      _beatsUsed = b[i].round();
    }
  }

  Future<void> _start() async {
    rr.clear();
    hrLine.clear();
    before = after = null;
    finished = false;
    if (strap) {
      _rrSub = hr.rr.stream.listen((r) {
        rr.add((sw.elapsedMilliseconds / 1000, r));
        hrLine.add(60000 / r);
      });
    } else if (useCamera) {
      await _startCam();
    }
    WakelockPlus.enable();
    sw
      ..reset()
      ..start();
    setState(() => running = true);
    timer = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
  }

  void _tick() {
    final t = sw.elapsedMilliseconds / 1000;
    final (inh, exh, _) = paces[pace];
    final cyc = inh + exh;
    final ph = (t % cyc) < inh ? 0 : 1;
    final k = (t % cyc) < inh ? (t % cyc) / inh : 1 - ((t % cyc) - inh) / exh;
    anim.value = k.clamp(0, 1).toDouble();
    final key = (t ~/ cyc) * 2 + ph;
    if (key != _lastPhase) {
      _lastPhase = key;
      Fx.instance.play(ph == 0 ? Sfx.tick : Sfx.go);
    }
    if (useCamera && !strap && (t * 10).round() % 10 == 0) _camBeats();
    if (t >= minutes * 60) _finish();
    setState(() {});
  }

  Future<void> _finish() async {
    timer?.cancel();
    sw.stop();
    await _rrSub?.cancel();
    _rrSub = null;
    await _stopCam();
    WakelockPlus.disable();
    Fx.instance.play(Sfx.finish);
    final end = sw.elapsedMilliseconds / 1000;
    before = rmssdOf([for (final (t, r) in rr) if (t < 75) r]);
    after = rmssdOf([for (final (t, r) in rr) if (t > end - 75) r]);
    if (after != null && hrLine.isNotEmpty) {
      final bpm = (hrLine.sublist(math.max(0, hrLine.length - 40)).reduce((a, b) => a + b) /
              math.min(40, hrLine.length))
          .round();
      await Store.instance.addHrv(HrvMeasure(DateTime.now(), after!, bpm, 'oddech'));
    }
    setState(() {
      running = false;
      finished = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final (inh, exh, _) = paces[pace];
    final t = sw.elapsedMilliseconds / 1000;
    final inhaling = (t % (inh + exh)) < inh;
    return Scaffold(
      appBar: AppBar(title: const Text('Oddychanie')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
        if (!running && !finished) ...[
          Text(
            'Spokojny oddech w rytmie ok. 6 na minutę uspokaja układ nerwowy — widać to w tętnie, które faluje razem z oddechem, '
            'i w HRV, które zwykle rośnie. Wdech nosem, długi wydech ustami.',
            style: TextStyle(color: C.muted, height: 1.35),
          ),
          const SizedBox(height: 12),
          SegmentedButton<int>(
            segments: [for (var i = 0; i < paces.length; i++) ButtonSegment(value: i, label: Text(paces[i].$3))],
            selected: {pace},
            onSelectionChanged: (v) => setState(() => pace = v.first),
          ),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 3, label: Text('3 min')),
              ButtonSegment(value: 5, label: Text('5 min')),
              ButtonSegment(value: 10, label: Text('10 min')),
            ],
            selected: {minutes},
            onSelectionChanged: (v) => setState(() => minutes = v.first),
          ),
          const SizedBox(height: 8),
          if (strap)
            ListTile(
              leading: const Icon(Icons.favorite, color: C.bad),
              title: const Text('Tętno z paska'),
              subtitle: Text('${hr.freshBpm} bpm — HRV przed i po', style: TextStyle(color: C.muted)),
            )
          else
            SwitchListTile(
              title: const Text('Mierz palcem na aparacie'),
              subtitle: Text('Opuszek na obiektywie i lampie przez cały czas', style: TextStyle(color: C.muted)),
              value: useCamera,
              onChanged: (v) => setState(() => useCamera = v),
            ),
          const SizedBox(height: 8),
          FilledButton.icon(onPressed: _start, icon: const Icon(Icons.air), label: const Text('Zacznij')),
        ],
        if (running) ...[
          const SizedBox(height: 24),
          Center(
            child: AnimatedBuilder(
              animation: anim,
              builder: (_, __) => Container(
                width: 120 + 140 * anim.value,
                height: 120 + 140 * anim.value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [C.calm.withValues(alpha: 0.85), C.calm.withValues(alpha: 0.15)]),
                ),
                alignment: Alignment.center,
                child: Text(inhaling ? 'wdech' : 'wydech',
                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text('${fmtDur((minutes * 60 - t).round().clamp(0, minutes * 60))}'
                '${hrLine.isNotEmpty ? ' · ${hrLine.last.round()} bpm' : ''}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          if (hrLine.length > 4) ...[
            const SizedBox(height: 8),
            TrendLine(hrLine.sublist(math.max(0, hrLine.length - 60)), color: C.bad, height: 70),
            Text('Tętno powinno rosnąć przy wdechu i spadać przy wydechu.',
                textAlign: TextAlign.center, style: TextStyle(color: C.muted, fontSize: 12)),
          ],
          const SizedBox(height: 16),
          OutlinedButton(onPressed: _finish, child: const Text('Zakończ')),
        ],
        if (finished) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                const Text('Gotowe', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                if (before != null && after != null)
                  Text('HRV: ${before!.round()} → ${after!.round()} ms '
                      '(${after! >= before! ? '+' : ''}${((after! / before! - 1) * 100).round()}%)',
                      style: TextStyle(fontSize: 18, color: after! >= before! ? C.good : C.warn, fontWeight: FontWeight.w700))
                else
                  Text(rr.isEmpty ? 'Bez pomiaru tętna — sama praktyka też działa.' : 'Za mało czystych uderzeń do HRV.',
                      style: TextStyle(color: C.muted)),
                if (hrLine.length > 10) ...[
                  const SizedBox(height: 12),
                  TrendLine(hrLine, color: C.bad, height: 70),
                ],
              ]),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(onPressed: () => setState(() => finished = false), child: const Text('Jeszcze raz')),
        ],
      ]),
    );
  }
}
