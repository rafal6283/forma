import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/models.dart';
import '../core/ppg.dart';
import '../core/store.dart';
import 'theme.dart';
import 'widgets.dart';

/// Średnia jasność środka kadru (czerwień na iOS, luminancja na Androidzie) i jej rozrzut.
(double, double) frameStats(CameraImage img) {
  final p = img.planes.first;
  final bytes = p.bytes;
  final w = img.width, h = img.height;
  final bgra = img.format.group == ImageFormatGroup.bgra8888;
  final px = bgra ? 4 : 1;
  var s = 0.0, s2 = 0.0, n = 0;
  for (var y = h ~/ 4; y < h * 3 ~/ 4; y += 6) {
    final row = y * p.bytesPerRow;
    for (var x = w ~/ 4; x < w * 3 ~/ 4; x += 6) {
      final i = row + x * px + (bgra ? 2 : 0);
      if (i >= bytes.length) continue;
      final v = bytes[i].toDouble();
      s += v;
      s2 += v * v;
      n++;
    }
  }
  if (n == 0) return (0, 0);
  final m = s / n;
  return (m, math.sqrt(math.max(0, s2 / n - m * m)));
}

/// Poranny pomiar HRV palcem na obiektywie (z lampą) — bez opaski.
class PpgScreen extends StatefulWidget {
  const PpgScreen({super.key});

  @override
  State<PpgScreen> createState() => _PpgScreenState();
}

class _PpgScreenState extends State<PpgScreen> {
  static const settle = 5, total = 65;
  CameraController? cam;
  String? error;
  final t = <double>[], v = <double>[];
  final sw = Stopwatch();
  bool running = false, finger = false;
  PpgResult? result;
  bool failed = false;
  Timer? timer;
  int liveBpm = 0;

  @override
  void dispose() {
    timer?.cancel();
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

  Future<void> _start() async {
    setState(() {
      error = null;
      result = null;
      failed = false;
    });
    try {
      final cams = await availableCameras();
      final back = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cams.first);
      final c = CameraController(
        back,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: Platform.isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.nv21,
      );
      await c.initialize();
      await c.setFlashMode(FlashMode.torch);
      cam = c;
      t.clear();
      v.clear();
      sw
        ..reset()
        ..start();
      running = true;
      WakelockPlus.enable();
      await c.startImageStream(_onFrame);
      timer = Timer.periodic(const Duration(milliseconds: 500), (_) => _tick());
      setState(() {});
    } catch (e) {
      setState(() => error = 'Nie udało się uruchomić aparatu: $e');
    }
  }

  void _onFrame(CameraImage img) {
    if (!running) return;
    final (m, sd) = frameStats(img);
    // palec z lampą: jasny, jednolity kadr
    final on = m > 25 && sd < 28;
    if (on != finger) finger = on;
    if (!on) {
      // zabrany palec: zaczynamy od nowa
      if (t.isNotEmpty) {
        t.clear();
        v.clear();
        sw.reset();
      }
      return;
    }
    t.add(sw.elapsedMicroseconds / 1000);
    v.add(m);
  }

  void _tick() {
    if (!running) return;
    final secs = t.isEmpty ? 0 : (t.last - t.first) / 1000;
    if (t.length > 90) {
      final from = t.length > 300 ? t.length - 300 : 0;
      final r = Ppg.analyze(t.sublist(from), v.sublist(from));
      liveBpm = r?.bpm ?? 0;
    }
    if (secs >= total) _finish();
    if (mounted) setState(() {});
  }

  Future<void> _finish() async {
    running = false;
    timer?.cancel();
    // pierwsze sekundy (ustawianie palca, ekspozycja) pomijamy
    final skip = t.indexWhere((x) => x - t.first >= settle * 1000);
    final r = skip < 0 ? null : Ppg.analyze(t.sublist(skip), v.sublist(skip));
    await _stopCam();
    WakelockPlus.disable();
    if (!mounted) return;
    setState(() {
      result = r;
      failed = r == null || r.rmssd == null;
    });
  }

  Future<void> _save() async {
    final r = result!;
    await Store.instance.addHrv(HrvMeasure(DateTime.now(), r.rmssd!, r.bpm, 'aparat'));
    if (mounted) {
      toast(context, 'Zapisano pomiar HRV');
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final secs = t.isEmpty ? 0.0 : (t.last - t.first) / 1000;
    final from = t.length > 150 ? t.length - 150 : 0;
    final wave = t.length > 20 ? Ppg.filtered(t.sublist(from), v.sublist(from)) : const <double>[];
    return Scaffold(
      appBar: AppBar(title: const Text('HRV aparatem')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Center(
          child: Ring(
            value: (secs / total).clamp(0, 1).toDouble(),
            color: finger || !running ? C.calm : C.warn,
            size: 200,
            width: 12,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(
                result?.rmssd != null
                    ? '${result!.rmssd!.round()}'
                    : running
                        ? (finger ? (liveBpm > 0 ? '$liveBpm' : '…') : '☝')
                        : '1:05',
                style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800),
              ),
              Text(
                result?.rmssd != null
                    ? 'ms RMSSD · ${result!.bpm} bpm'
                    : running
                        ? (finger ? (liveBpm > 0 ? 'bpm · ${fmtDur((total - secs).round().clamp(0, total))}' : 'szukam pulsu') : 'połóż palec na obiektywie')
                        : 'palec na aparacie',
                style: TextStyle(color: C.muted),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(height: 60, child: CustomPaint(painter: _Wave(wave), size: Size.infinite)),
        const SizedBox(height: 12),
        if (error != null) Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: C.bad)),
        if (!running && result == null && !failed)
          FilledButton.icon(onPressed: _start, icon: const Icon(Icons.fingerprint), label: const Text('Rozpocznij pomiar'))
        else if (running)
          OutlinedButton(onPressed: _finish, child: const Text('Zakończ'))
        else ...[
          if (failed)
            const Text(
              'Sygnał był za słaby albo za dużo zakłóceń. Przyłóż opuszek lekko (bez nacisku) tak, '
              'by zakrył obiektyw i lampę, i nie ruszaj się.',
              textAlign: TextAlign.center,
              style: TextStyle(color: C.bad),
            )
          else
            Text('Jakość sygnału: ${(result!.quality * 100).round()}%', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: _start, child: const Text('Powtórz'))),
            const SizedBox(width: 10),
            if (!failed) Expanded(child: FilledButton(onPressed: _save, child: const Text('Zapisz'))),
          ]),
        ],
        const SizedBox(height: 24),
        Text(
          'Rano, w leżeniu lub siedząc, przyłóż opuszek palca wskazującego do tylnego aparatu tak, żeby zakrył też lampę. '
          'Nie naciskaj mocno i nie ruszaj ręką przez minutę. Wynik jest mniej dokładny niż z paska na klatkę, '
          'ale do śledzenia trendu wystarczy — mierz zawsze tak samo.',
          style: TextStyle(color: C.muted, height: 1.4),
        ),
      ]),
    );
  }
}

class _Wave extends CustomPainter {
  final List<double> w;
  _Wave(this.w);

  @override
  void paint(Canvas canvas, Size size) {
    if (w.length < 2) return;
    final mx = w.map((e) => e.abs()).fold(0.0, math.max);
    if (mx == 0) return;
    final path = Path();
    for (var i = 0; i < w.length; i++) {
      final x = size.width * i / (w.length - 1);
      final y = size.height / 2 - w[i] / mx * size.height * 0.45;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = C.bad
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_Wave o) => true;
}
