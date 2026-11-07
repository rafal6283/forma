import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart' as mk;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/models.dart';
import '../core/rep_counter.dart';
import '../core/sfx.dart';
import '../core/voice.dart';
import 'figure_view.dart';
import 'theme.dart';

/// Wynik liczenia kamerą: powtórzenia i ocena zakresu (0–100).
class CamReps {
  final int reps;
  final int? rom;
  const CamReps(this.reps, this.rom);
}

const _keys = {
  mk.PoseLandmarkType.leftShoulder: 'shoulderL',
  mk.PoseLandmarkType.rightShoulder: 'shoulderR',
  mk.PoseLandmarkType.leftElbow: 'elbowL',
  mk.PoseLandmarkType.rightElbow: 'elbowR',
  mk.PoseLandmarkType.leftWrist: 'wristL',
  mk.PoseLandmarkType.rightWrist: 'wristR',
  mk.PoseLandmarkType.leftHip: 'hipL',
  mk.PoseLandmarkType.rightHip: 'hipR',
  mk.PoseLandmarkType.leftKnee: 'kneeL',
  mk.PoseLandmarkType.rightKnee: 'kneeR',
  mk.PoseLandmarkType.leftAnkle: 'ankleL',
  mk.PoseLandmarkType.rightAnkle: 'ankleR',
  mk.PoseLandmarkType.nose: 'nose',
};

const _bones = [
  ('shoulderL', 'shoulderR'), ('hipL', 'hipR'), ('shoulderL', 'hipL'), ('shoulderR', 'hipR'),
  ('shoulderL', 'elbowL'), ('elbowL', 'wristL'), ('shoulderR', 'elbowR'), ('elbowR', 'wristR'),
  ('hipL', 'kneeL'), ('kneeL', 'ankleL'), ('hipR', 'kneeR'), ('kneeR', 'ankleR'),
];

/// Liczenie powtórzeń kamerą z oceną zakresu ruchu i sylwetką nałożoną na animację.
class PoseScreen extends StatefulWidget {
  final Exercise exercise;
  final int? target;
  const PoseScreen({super.key, required this.exercise, this.target});

  @override
  State<PoseScreen> createState() => _PoseScreenState();
}

class _PoseScreenState extends State<PoseScreen> {
  late final RepModel? model = RepModel.of(widget.exercise);
  late final RepCounter? counter = model == null ? null : RepCounter(model!);
  final detector = mk.PoseDetector(options: mk.PoseDetectorOptions());
  CameraController? cam;
  List<CameraDescription> cams = const [];
  bool front = true, busy = false;
  String? error;
  Map<String, P3> pts = const {};
  Size imgSize = Size.zero; // obraz po obrocie (pionowo)
  final sw = Stopwatch()..start();

  @override
  void initState() {
    super.initState();
    if (model != null) _open();
  }

  @override
  void dispose() {
    _close();
    detector.close();
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _close() async {
    final c = cam;
    cam = null;
    if (c == null) return;
    try {
      if (c.value.isStreamingImages) await c.stopImageStream();
    } catch (_) {}
    await c.dispose();
  }

  Future<void> _open() async {
    try {
      await _close();
      if (cams.isEmpty) cams = await availableCameras();
      final dir = front ? CameraLensDirection.front : CameraLensDirection.back;
      final d = cams.firstWhere((c) => c.lensDirection == dir, orElse: () => cams.first);
      final c = CameraController(
        d,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.nv21,
      );
      await c.initialize();
      cam = c;
      WakelockPlus.enable();
      await c.startImageStream((img) => _frame(img, d));
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => error = 'Aparat niedostępny: $e');
    }
  }

  Future<void> _frame(CameraImage img, CameraDescription d) async {
    if (busy) return;
    busy = true;
    try {
      final rot = mk.InputImageRotationValue.fromRawValue(d.sensorOrientation) ?? mk.InputImageRotation.rotation0deg;
      final fmt = mk.InputImageFormatValue.fromRawValue(img.format.raw as int);
      if (fmt == null || img.planes.isEmpty) return;
      final bytes = img.planes.length == 1
          ? img.planes.first.bytes
          : Uint8List.fromList([for (final p in img.planes) ...p.bytes]);
      final input = mk.InputImage.fromBytes(
        bytes: bytes,
        metadata: mk.InputImageMetadata(
          size: Size(img.width.toDouble(), img.height.toDouble()),
          rotation: rot,
          format: fmt,
          bytesPerRow: img.planes.first.bytesPerRow,
        ),
      );
      final poses = await detector.processImage(input);
      final upright = (rot == mk.InputImageRotation.rotation90deg || rot == mk.InputImageRotation.rotation270deg)
          ? Size(img.height.toDouble(), img.width.toDouble())
          : Size(img.width.toDouble(), img.height.toDouble());
      final m = <String, P3>{};
      if (poses.isNotEmpty) {
        poses.first.landmarks.forEach((t, l) {
          final k = _keys[t];
          if (k != null) m[k] = P3(l.x, l.y, l.z, l.likelihood);
        });
      }
      final c = counter;
      if (c != null && m.isNotEmpty) {
        final a = cameraAngle(m, model!);
        if (a != null && c.add(a, sw.elapsedMilliseconds.toDouble())) {
          Fx.instance.play(Sfx.tick);
          final cue = c.cue;
          Voice.instance.say(cue != null && c.lastRom! < 0.8 ? '${c.reps}. $cue' : '${c.reps}');
        }
      }
      if (mounted) {
        setState(() {
          pts = m;
          imgSize = upright;
        });
      }
    } catch (e) {
      debugPrint('poza: $e');
    } finally {
      busy = false;
    }
  }

  void _done() => Navigator.pop(context, CamReps(counter?.reps ?? 0, counter?.score));

  @override
  Widget build(BuildContext context) {
    final c = cam;
    final cnt = counter;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.exercise.name),
        actions: [
          IconButton(
            tooltip: 'Zmień aparat',
            onPressed: () {
              front = !front;
              _open();
            },
            icon: const Icon(Icons.cameraswitch_outlined),
          ),
        ],
      ),
      body: model == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text('To ćwiczenie jest statyczne albo ma za mały zakres ruchu, żeby liczyć je kamerą.',
                    textAlign: TextAlign.center, style: TextStyle(color: C.muted)),
              ),
            )
          : Stack(fit: StackFit.expand, children: [
              if (c != null && c.value.isInitialized && imgSize != Size.zero)
                ClipRect(
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: imgSize.width,
                      height: imgSize.height,
                      child: Stack(fit: StackFit.expand, children: [
                        CameraPreview(c),
                        CustomPaint(painter: _SkeletonPainter(pts, imgSize, mirror: front, track: model!.track)),
                      ]),
                    ),
                  ),
                )
              else if (c != null && c.value.isInitialized)
                Center(child: CameraPreview(c))
              else
                Center(
                  child: error != null
                      ? Text(error!, style: const TextStyle(color: C.bad))
                      : const CircularProgressIndicator(),
                ),
              // licznik i ocena
              Positioned(
                top: 12,
                right: 12,
                child: _Badge(children: [
                  Text('${cnt!.reps}${widget.target != null ? '/${widget.target}' : ''}',
                      style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w900, color: Colors.white)),
                  Text('powtórzenia', style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12)),
                  if (cnt.score != null) ...[
                    const SizedBox(height: 6),
                    Text('zakres ${cnt.score}%',
                        style: TextStyle(
                            color: cnt.score! >= 85 ? C.good : (cnt.score! >= 65 ? C.warn : C.bad),
                            fontWeight: FontWeight.w800)),
                  ],
                ]),
              ),
              // pasek bieżącego zakresu
              Positioned(
                top: 12,
                left: 12,
                bottom: 200,
                child: _RomBar(value: cnt.current, label: trackLabel[model!.track]!),
              ),
              // animacja wzorcowa z nałożoną sylwetką
              Positioned(
                left: 12,
                bottom: 88,
                width: 150,
                height: 150,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    color: C.surface.withValues(alpha: 0.85),
                    child: Stack(fit: StackFit.expand, children: [
                      FigureView(widget.exercise, playing: true, showFloor: false),
                      CustomPaint(painter: _MiniOverlay(pts, mirror: front)),
                    ]),
                  ),
                ),
              ),
              if (cnt.cue != null)
                Positioned(
                  right: 12,
                  bottom: 100,
                  child: _Badge(children: [
                    Text(cnt.cue!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ]),
                ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 20,
                child: SafeArea(
                  child: Row(children: [
                    Expanded(
                      child: Text(
                        pts.isEmpty ? 'Stań tak, żeby było Cię widać całego' : 'Najlepiej bokiem do telefonu, 2–3 m dalej',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                    FilledButton(onPressed: _done, child: const Text('Gotowe')),
                  ]),
                ),
              ),
            ]),
    );
  }
}

class _Badge extends StatelessWidget {
  final List<Widget> children;
  const _Badge({required this.children});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(16)),
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      );
}

class _RomBar extends StatelessWidget {
  final double value;
  final String label;
  const _RomBar({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(0.0, 1.2) / 1.2;
    return Column(children: [
      Expanded(
        child: Container(
          width: 16,
          decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(8)),
          alignment: Alignment.bottomCenter,
          child: Stack(alignment: Alignment.bottomCenter, children: [
            FractionallySizedBox(
              heightFactor: v,
              child: Container(
                decoration: BoxDecoration(
                  color: value >= 0.9 ? C.good : (value >= RepCounter.enter ? C.warn : C.accent),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            // znacznik pełnego zakresu
            FractionallySizedBox(heightFactor: 1 / 1.2, child: Container(alignment: Alignment.topCenter, child: Container(height: 2, color: Colors.white))),
          ]),
        ),
      ),
      const SizedBox(height: 4),
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
    ]);
  }
}

class _SkeletonPainter extends CustomPainter {
  final Map<String, P3> pts;
  final Size img;
  final bool mirror;
  final Track track;
  _SkeletonPainter(this.pts, this.img, {required this.mirror, required this.track});

  Offset _o(P3 p, Size size) {
    final x = p.x / img.width * size.width;
    return Offset(mirror ? size.width - x : x, p.y / img.height * size.height);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (pts.isEmpty) return;
    final w = size.shortestSide / 90;
    final bone = Paint()
      ..color = C.accent.withValues(alpha: 0.85)
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round;
    for (final (a, b) in _bones) {
      final pa = pts[a], pb = pts[b];
      if (pa == null || pb == null || pa.conf < 0.4 || pb.conf < 0.4) continue;
      canvas.drawLine(_o(pa, size), _o(pb, size), bone);
    }
    final joint = switch (track) {
      Track.knee => 'knee',
      Track.hip => 'hip',
      Track.elbow => 'elbow',
      Track.shoulder => 'shoulder',
    };
    for (final e in pts.entries) {
      if (e.value.conf < 0.4 || e.key == 'nose') continue;
      final hot = e.key.startsWith(joint);
      canvas.drawCircle(_o(e.value, size), hot ? w * 2.2 : w * 1.2, Paint()..color = hot ? C.warn : Colors.white);
    }
  }

  @override
  bool shouldRepaint(_SkeletonPainter o) => true;
}

/// Sylwetka z kamery przeskalowana i nałożona na animację wzorcową (biodra w środku, tułów jak w postaci).
class _MiniOverlay extends CustomPainter {
  final Map<String, P3> pts;
  final bool mirror;
  _MiniOverlay(this.pts, {required this.mirror});

  @override
  void paint(Canvas canvas, Size size) {
    P3? mid(String a, String b) {
      final pa = pts[a], pb = pts[b];
      if (pa == null || pb == null) return pa ?? pb;
      return P3((pa.x + pb.x) / 2, (pa.y + pb.y) / 2);
    }

    final hip = mid('hipL', 'hipR'), sh = mid('shoulderL', 'shoulderR');
    if (hip == null || sh == null) return;
    final torso = math.sqrt(math.pow(sh.x - hip.x, 2) + math.pow(sh.y - hip.y, 2));
    if (torso < 1) return;
    // w animacji tułów to ok. 28% wysokości kadru
    final k = size.height * 0.28 / torso;
    final c = Offset(size.width / 2, size.height * 0.52);
    Offset o(P3 p) => c + Offset((mirror ? -1 : 1) * (p.x - hip.x) * k, (p.y - hip.y) * k);
    final paint = Paint()
      ..color = C.calm.withValues(alpha: 0.85)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (final (a, b) in _bones) {
      final pa = pts[a], pb = pts[b];
      if (pa == null || pb == null || pa.conf < 0.4 || pb.conf < 0.4) continue;
      canvas.drawLine(o(pa), o(pb), paint);
    }
  }

  @override
  bool shouldRepaint(_MiniOverlay o) => true;
}
