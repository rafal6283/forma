import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart' as mk;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/rep_counter.dart';
import 'theme.dart';

const poseKeys = {
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
  mk.PoseLandmarkType.leftEar: 'earL',
  mk.PoseLandmarkType.rightEar: 'earR',
  mk.PoseLandmarkType.nose: 'nose',
};

const poseBones = [
  ('shoulderL', 'shoulderR'), ('hipL', 'hipR'), ('shoulderL', 'hipL'), ('shoulderR', 'hipR'),
  ('shoulderL', 'elbowL'), ('elbowL', 'wristL'), ('shoulderR', 'elbowR'), ('elbowR', 'wristR'),
  ('hipL', 'kneeL'), ('kneeL', 'ankleL'), ('hipR', 'kneeR'), ('kneeR', 'ankleR'), ('earL', 'earR'),
];

Map<String, P3> _points(List<mk.Pose> poses) {
  final m = <String, P3>{};
  if (poses.isNotEmpty) {
    poses.first.landmarks.forEach((t, l) {
      final k = poseKeys[t];
      if (k != null) m[k] = P3(l.x, l.y, l.z, l.likelihood);
    });
  }
  return m;
}

/// Punkty ciała ze zdjęcia (plik). Pusta mapa, gdy nikogo nie wykryto.
Future<Map<String, P3>> detectPoseInFile(String path) async {
  final det = mk.PoseDetector(options: mk.PoseDetectorOptions(mode: mk.PoseDetectionMode.single));
  try {
    return _points(await det.processImage(mk.InputImage.fromFilePath(path)));
  } finally {
    await det.close();
  }
}

/// Podgląd z kamery z wykrywaniem sylwetki: wywołuje [onPoints] dla każdej klatki, rysuje szkielet.
/// Kontroler [ctl] pozwala zrobić zdjęcie (np. do oceny postawy).
class PoseCamera extends StatefulWidget {
  final bool front;
  final void Function(Map<String, P3> pts)? onPoints;
  final PoseCameraController? ctl;
  final Widget? overlay; // np. poprzednie zdjęcie jako „duch”
  final bool detect;
  const PoseCamera({super.key, this.front = true, this.onPoints, this.ctl, this.overlay, this.detect = true});

  @override
  State<PoseCamera> createState() => _PoseCameraState();
}

class PoseCameraController {
  _PoseCameraState? _s;

  /// Zdjęcie (ścieżka do pliku) — wstrzymuje na chwilę analizę obrazu.
  Future<String?> takePicture() async => _s?._take();
  Future<void> switchCamera() async => _s?._switch();
}

class _PoseCameraState extends State<PoseCamera> {
  final det = mk.PoseDetector(options: mk.PoseDetectorOptions());
  CameraController? cam;
  CameraDescription? desc;
  late bool front = widget.front;
  bool busy = false;
  String? error;
  Map<String, P3> pts = const {};
  Size img = Size.zero;

  @override
  void initState() {
    super.initState();
    widget.ctl?._s = this;
    _open();
  }

  @override
  void dispose() {
    _close();
    det.close();
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

  Future<void> _switch() async {
    front = !front;
    await _open();
  }

  Future<void> _open() async {
    try {
      await _close();
      final cams = await availableCameras();
      final dir = front ? CameraLensDirection.front : CameraLensDirection.back;
      final d = cams.firstWhere((c) => c.lensDirection == dir, orElse: () => cams.first);
      final c = CameraController(d, ResolutionPreset.high,
          enableAudio: false, imageFormatGroup: Platform.isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.nv21);
      await c.initialize();
      cam = c;
      desc = d;
      WakelockPlus.enable();
      if (widget.detect) await c.startImageStream(_frame);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => error = 'Aparat niedostępny: $e');
    }
  }

  Future<String?> _take() async {
    final c = cam;
    if (c == null) return null;
    try {
      if (c.value.isStreamingImages) await c.stopImageStream();
      final f = await c.takePicture();
      if (widget.detect && mounted) await c.startImageStream(_frame);
      return f.path;
    } catch (e) {
      debugPrint('zdjęcie: $e');
      return null;
    }
  }

  Future<void> _frame(CameraImage im) async {
    if (busy || desc == null) return;
    busy = true;
    try {
      final rot = mk.InputImageRotationValue.fromRawValue(desc!.sensorOrientation) ?? mk.InputImageRotation.rotation0deg;
      final fmt = mk.InputImageFormatValue.fromRawValue(im.format.raw as int);
      if (fmt == null || im.planes.isEmpty) return;
      final bytes =
          im.planes.length == 1 ? im.planes.first.bytes : Uint8List.fromList([for (final p in im.planes) ...p.bytes]);
      final poses = await det.processImage(mk.InputImage.fromBytes(
        bytes: bytes,
        metadata: mk.InputImageMetadata(
          size: Size(im.width.toDouble(), im.height.toDouble()),
          rotation: rot,
          format: fmt,
          bytesPerRow: im.planes.first.bytesPerRow,
        ),
      ));
      final up = (rot == mk.InputImageRotation.rotation90deg || rot == mk.InputImageRotation.rotation270deg)
          ? Size(im.height.toDouble(), im.width.toDouble())
          : Size(im.width.toDouble(), im.height.toDouble());
      final m = _points(poses);
      widget.onPoints?.call(m);
      if (mounted) {
        setState(() {
          pts = m;
          img = up;
        });
      }
    } catch (e) {
      debugPrint('poza: $e');
    } finally {
      busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = cam;
    if (c == null || !c.value.isInitialized) {
      return Center(
          child: error != null ? Text(error!, style: const TextStyle(color: C.bad)) : const CircularProgressIndicator());
    }
    final size = img != Size.zero
        ? img
        : Size(c.value.previewSize?.height ?? 720, c.value.previewSize?.width ?? 1280); // pionowo
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: Stack(fit: StackFit.expand, children: [
            CameraPreview(c),
            if (widget.overlay != null) widget.overlay!,
            if (widget.detect) CustomPaint(painter: SkeletonPainter(pts, size, mirror: front)),
          ]),
        ),
      ),
    );
  }
}

class SkeletonPainter extends CustomPainter {
  final Map<String, P3> pts;
  final Size img;
  final bool mirror;
  SkeletonPainter(this.pts, this.img, {required this.mirror});

  @override
  void paint(Canvas canvas, Size size) {
    if (pts.isEmpty || img == Size.zero) return;
    Offset o(P3 p) {
      final x = p.x / img.width * size.width;
      return Offset(mirror ? size.width - x : x, p.y / img.height * size.height);
    }

    final w = size.shortestSide / 90;
    final bone = Paint()
      ..color = C.accent.withValues(alpha: 0.85)
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round;
    for (final (a, b) in poseBones) {
      final pa = pts[a], pb = pts[b];
      if (pa == null || pb == null || pa.conf < 0.4 || pb.conf < 0.4) continue;
      canvas.drawLine(o(pa), o(pb), bone);
    }
    for (final v in pts.values) {
      if (v.conf >= 0.4) canvas.drawCircle(o(v), w * 1.2, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(SkeletonPainter o) => true;
}
