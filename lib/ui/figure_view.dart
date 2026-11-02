import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/figure.dart';
import '../core/models.dart';
import '../core/app_settings.dart';
import 'figure3d.dart';
import 'mannequin.dart';
import 'technique.dart';
import 'theme.dart';

/// Animowana postać wykonująca ćwiczenie: 2D (profil) albo 3D z obrotem kamery,
/// z podświetleniem pracujących mięśni i strzałką ruchu.
class FigureView extends StatefulWidget {
  final Exercise exercise;
  final bool playing;
  final double speed;
  final bool showFloor;

  /// Wskazówki techniki: świecące mięśnie i strzałka kierunku ruchu.
  final bool hints;

  /// Duży widok: 3D (wg ustawień), obrót palcem, przełącznik 2D/3D.
  final bool interactive;

  const FigureView(
    this.exercise, {
    super.key,
    this.playing = true,
    this.speed = 1,
    this.showFloor = true,
    this.hints = false,
    this.interactive = false,
  });

  @override
  State<FigureView> createState() => _FigureViewState();
}

class _FigureViewState extends State<FigureView> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _t = 0;
  Duration _last = Duration.zero;
  late _Scene _scene;
  final settings = AppSettings.instance;

  // kamera 3D
  static const _pitch = 0.2;
  double _yaw = 0.55;
  bool _dragged = false;
  final _frames = <int, Rect>{};

  @override
  void initState() {
    super.initState();
    _scene = _Scene(widget.exercise);
    _ticker = createTicker((d) {
      final dt = (d - _last).inMicroseconds / 1e6;
      _last = d;
      if (dt > 0 && dt < 0.2) setState(() => _t += dt);
    });
    if (widget.playing) _ticker.start();
  }

  @override
  void didUpdateWidget(FigureView old) {
    super.didUpdateWidget(old);
    if (old.exercise.id != widget.exercise.id) {
      _scene = _Scene(widget.exercise);
      _frames.clear();
      _t = 0;
    }
    if (widget.playing && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    } else if (!widget.playing && _ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  /// Pozycja trzymana (deska, rozciąganie) — postać „oddycha”, żeby nie była martwa.
  bool get _still => widget.exercise.isStatic || widget.exercise.anim.keys.length == 1;

  bool get _is3d => widget.interactive && settings.anim3d;

  double get _yawNow => _dragged ? _yaw : _yaw + 0.12 * math.sin(_t * 0.45);

  Rect _frame(Cam cam) {
    final key = (cam.yaw * 30).round(); // co ~2°
    return _frames.putIfAbsent(key, () => frame3d(_scene.samples, cam, floor: widget.showFloor && !_scene.ex.anim.hands));
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.exercise.anim;
    final pose = a.at(_t, speed: widget.speed);
    final breath = _still ? math.sin(_t * 2 * math.pi / 3.6) : 0.0;
    final j = Joints.grounded(pose, hands: a.hands);

    // wskazówki techniki
    var glow = const <String, double>{};
    (Offset, Offset, double)? arrow;
    if (widget.hints && settings.technique) {
      final (target, move) = a.motion(_t, speed: widget.speed);
      final level = _still ? 0.55 + 0.2 * breath : 0.2 + 0.8 * move;
      glow = _scene.glow.map((k, v) => MapEntry(k, v * level));
      if (move > 0.08) {
        final m = moveArrow(j, Joints.grounded(target, hands: a.hands));
        if (m != null) arrow = (m.$2, m.$3, move);
      }
    }

    final CustomPainter painter;
    if (_is3d) {
      final cam = Cam(_yawNow, _pitch, _scene.cx, 0);
      painter = Figure3DPainter(
        j: j,
        cam: cam,
        bounds: _frame(cam),
        floor: widget.showFloor,
        hands: a.hands,
        hold: widget.exercise.hold,
        props: [for (final p in _scene.props) Prop3(p.type, p.rect)],
        breath: breath,
        glow: glow,
        arrow: arrow,
      );
    } else {
      painter = _FigurePainter(_scene, pose, widget.showFloor, breath: breath, glow: glow, arrow: arrow);
    }
    Widget view = RepaintBoundary(child: CustomPaint(painter: painter, size: Size.infinite));
    if (!widget.interactive) return view;
    return Stack(children: [
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: _is3d
              ? (d) => setState(() {
                    if (!_dragged) _yaw = _yawNow;
                    _dragged = true;
                    _yaw -= d.delta.dx / 120;
                  })
              : null,
          onDoubleTap: _is3d
              ? () => setState(() {
                    _dragged = false;
                    _yaw = 0.55;
                  })
              : null,
          child: view,
        ),
      ),
      Positioned(
        top: 0,
        right: 0,
        child: _ModeChip(
          is3d: _is3d,
          onTap: () {
            settings.set(anim3d: !settings.anim3d);
            setState(() {});
          },
        ),
      ),
    ]);
  }
}

/// Mały przełącznik 2D/3D w rogu animacji.
class _ModeChip extends StatelessWidget {
  final bool is3d;
  final VoidCallback onTap;
  const _ModeChip({required this.is3d, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: C.surface2.withValues(alpha: 0.85),
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(is3d ? Icons.threed_rotation : Icons.view_in_ar_outlined, size: 16, color: C.text),
              const SizedBox(width: 4),
              Text(is3d ? '3D · obróć palcem' : '2D', style: TextStyle(fontSize: 11, color: C.text)),
            ]),
          ),
        ),
      );
}

/// Stałe elementy sceny i kadr obejmujący całą animację (żeby postać nie „skakała”).
class _Scene {
  final Exercise ex;
  late final Rect bounds;
  late final List<_Prop> props;
  late final List<Joints> samples; // pozycje w całym cyklu (kadr 3D)
  late final Map<String, double> glow = glowFor(ex);
  late final double cx; // środek sceny (oś obrotu kamery)

  _Scene(this.ex) {
    final a = ex.anim;
    final first = Joints.grounded(a.keys.first, hands: a.hands);
    props = [
      for (final p in a.props) _Prop.from(p, first),
    ];
    var r = Rect.fromPoints(first['hip'], first['hip']);
    // próbkujemy cały cykl
    samples = [for (var i = 0; i <= 24; i++) Joints.grounded(a.at(a.cycle * i / 24), hands: a.hands)];
    for (final j in samples) {
      for (final v in j.p.values) {
        r = r.expandToInclude(Rect.fromCircle(center: v, radius: 0.04));
      }
      r = r.expandToInclude(Rect.fromCircle(center: j['head'], radius: Body.headR + 0.03));
    }
    for (final p in props) {
      r = r.expandToInclude(p.rect);
    }
    if (!a.hands) r = r.expandToInclude(Rect.fromLTRB(r.left, r.top, r.right, 0.02));
    // minimalny kadr, żeby małe ruchy nie były przeskalowane
    final w = math.max(r.width, 1.2), h = math.max(r.height, 1.3);
    bounds = Rect.fromCenter(center: r.center, width: w + 0.3, height: h + 0.25);
    cx = r.center.dx;
  }
}

class _Prop {
  final String type;
  final Rect rect;
  _Prop(this.type, this.rect);

  static _Prop from(Map<String, dynamic> p, Joints first) {
    switch (p['type']) {
      case 'chair':
        final pt = first[(p['at'] as String?) ?? 'haN'];
        final w = (p['w'] as num?)?.toDouble() ?? 0.4;
        final x0 = pt.dx + ((p['dx'] as num?)?.toDouble() ?? 0) - w / 2;
        return _Prop('chair', Rect.fromLTRB(x0, pt.dy, x0 + w, 0));
      case 'wall':
        final at = p['at'] as String?;
        final x = at != null
            ? first[at].dx + ((p['dx'] as num?)?.toDouble() ?? 0)
            : (p['x'] as num?)?.toDouble() ?? -0.1;
        return _Prop('wall', Rect.fromLTRB(x, -1.9, x + 0.04, 0));
      case 'bar':
        final h = first['haN'];
        return _Prop('bar', Rect.fromLTRB(h.dx - 0.55, h.dy - 0.02, h.dx + 0.55, h.dy + 0.02));
    }
    return _Prop('none', Rect.zero);
  }
}

class _FigurePainter extends CustomPainter {
  final _Scene scene;
  final Pose pose;
  final bool floor;

  /// Faza oddechu (-1…1) — widoczna w pozycjach statycznych.
  final double breath;
  final Map<String, double> glow;
  final (Offset, Offset, double)? arrow;
  _FigurePainter(this.scene, this.pose, this.floor, {this.breath = 0, this.glow = const {}, this.arrow});

  @override
  void paint(Canvas canvas, Size size) {
    final b = scene.bounds;
    final s = math.min(size.width / b.width, size.height / b.height);
    final dx = (size.width - b.width * s) / 2 - b.left * s;
    final dy = (size.height - b.height * s) / 2 - b.top * s;
    Offset P(Offset p) => Offset(p.dx * s + dx, p.dy * s + dy);

    final j = Joints.grounded(pose, hands: scene.ex.anim.hands);

    if (floor && !scene.ex.anim.hands) {
      final y = P(Offset.zero).dy;
      final fp = Paint()
        ..shader = LinearGradient(colors: [C.line.withValues(alpha: 0), C.line, C.line.withValues(alpha: 0)])
            .createShader(Rect.fromLTWH(0, y, size.width, 2))
        ..strokeWidth = 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), fp);
      Mannequin(canvas, j, P, s).floorShadow();
    }

    final propPaint = Paint()
      ..color = C.prop
      ..strokeWidth = math.max(2.0, s * 0.03)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final p in scene.props) {
      final r = Rect.fromPoints(P(p.rect.topLeft), P(p.rect.bottomRight));
      switch (p.type) {
        case 'chair':
          canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromLTWH(r.left, r.top, r.width, s * 0.05), Radius.circular(s * 0.02)),
            Paint()..color = C.prop,
          );
          canvas.drawLine(Offset(r.left + s * 0.03, r.top), Offset(r.left + s * 0.03, r.bottom), propPaint);
          canvas.drawLine(Offset(r.right - s * 0.03, r.top), Offset(r.right - s * 0.03, r.bottom), propPaint);
        case 'wall':
          canvas.drawRect(r, Paint()..color = C.surface2);
        case 'bar':
          canvas.drawLine(r.centerLeft, r.centerRight, propPaint..strokeWidth = math.max(3.0, s * 0.035));
      }
    }

    final front = pose.front;
    final man = Mannequin(canvas, j, P, s, breath: breath, glow: glow);
    man.paint();

    final hold = scene.ex.hold;
    if (hold != null) {
      final hp = Paint()..color = const Color(0xFF4A5262);
      final single = hold == 'kb' || hold == 'db1';
      for (final k in single ? ['haN'] : (front ? ['haN', 'haF'] : ['haF', 'haN'])) {
        final c = P(j[k]);
        switch (hold) {
          case 'kb':
            canvas.drawCircle(c + Offset(0, s * 0.07), s * 0.07, hp);
          case 'band':
            break;
          default:
            final r = Rect.fromCenter(center: c, width: s * 0.16, height: s * 0.06);
            canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(s * 0.02)), hp);
        }
      }
      if (hold == 'band') {
        canvas.drawLine(
          P(j['haN']),
          P(j['haF']),
          Paint()
            ..color = C.accent
            ..strokeWidth = math.max(2.0, s * 0.02),
        );
      }
    }

    final ar = arrow;
    if (ar != null) paintArrow(canvas, P(ar.$1), P(ar.$2), ar.$3, size.shortestSide);
  }

  @override
  bool shouldRepaint(_FigurePainter old) => true;
}

/// Statyczna miniatura (pierwsza poza) — tanie w listach.
class FigureThumb extends StatelessWidget {
  final Exercise exercise;
  final double size;
  const FigureThumb(this.exercise, {super.key, this.size = 56});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.all(4),
        child: FigureView(exercise, playing: false, showFloor: false),
      );
}
