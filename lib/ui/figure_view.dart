import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/figure.dart';
import '../core/models.dart';
import 'theme.dart';

/// Animowana postać wykonująca ćwiczenie.
class FigureView extends StatefulWidget {
  final Exercise exercise;
  final bool playing;
  final double speed;
  final bool showFloor;

  const FigureView(this.exercise, {super.key, this.playing = true, this.speed = 1, this.showFloor = true});

  @override
  State<FigureView> createState() => _FigureViewState();
}

class _FigureViewState extends State<FigureView> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _t = 0;
  Duration _last = Duration.zero;
  late _Scene _scene;

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

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(
          painter: _FigurePainter(_scene, widget.exercise.anim.at(_t, speed: widget.speed), widget.showFloor),
          size: Size.infinite,
        ),
      );
}

/// Stałe elementy sceny i kadr obejmujący całą animację (żeby postać nie „skakała”).
class _Scene {
  final Exercise ex;
  late final Rect bounds;
  late final List<_Prop> props;

  _Scene(this.ex) {
    final a = ex.anim;
    final first = Joints.grounded(a.keys.first, hands: a.hands);
    props = [
      for (final p in a.props) _Prop.from(p, first),
    ];
    var r = Rect.fromPoints(first['hip'], first['hip']);
    // próbkujemy cały cykl
    for (var i = 0; i <= 24; i++) {
      final j = Joints.grounded(a.at(a.cycle * i / 24), hands: a.hands);
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
        final x = (p['x'] as num?)?.toDouble() ?? -0.1;
        return _Prop('wall', Rect.fromLTRB(x - 0.04, -1.9, x, 0));
      case 'bar':
        final y = first['haN'].dy;
        return _Prop('bar', Rect.fromLTRB(-0.55, y - 0.02, 0.55, y + 0.02));
    }
    return _Prop('none', Rect.zero);
  }
}

class _FigurePainter extends CustomPainter {
  final _Scene scene;
  final Pose pose;
  final bool floor;
  _FigurePainter(this.scene, this.pose, this.floor);

  @override
  void paint(Canvas canvas, Size size) {
    final b = scene.bounds;
    final s = math.min(size.width / b.width, size.height / b.height);
    final dx = (size.width - b.width * s) / 2 - b.left * s;
    final dy = (size.height - b.height * s) / 2 - b.top * s;
    Offset P(Offset p) => Offset(p.dx * s + dx, p.dy * s + dy);

    final j = Joints.grounded(pose, hands: scene.ex.anim.hands);
    final limbW = math.max(3.0, s * 0.055);

    if (floor && !scene.ex.anim.hands) {
      final y = P(Offset.zero).dy;
      final fp = Paint()
        ..shader = LinearGradient(colors: [C.line.withValues(alpha: 0), C.line, C.line.withValues(alpha: 0)])
            .createShader(Rect.fromLTWH(0, y, size.width, 2))
        ..strokeWidth = 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), fp);
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

    Paint limb(Color c) => Paint()
      ..color = c
      ..strokeWidth = limbW
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    void chain(List<String> keys, Paint p) {
      final path = Path()..moveTo(P(j[keys.first]).dx, P(j[keys.first]).dy);
      for (final k in keys.skip(1)) {
        path.lineTo(P(j[k]).dx, P(j[k]).dy);
      }
      canvas.drawPath(path, p);
    }

    final front = pose.front;
    final far = limb(front ? C.figure : C.figureFar);
    final near = limb(C.figure);
    final body = limb(C.figure)..strokeWidth = limbW * 1.7;

    chain(['hpF', 'knF', 'anF', 'toF'], far);
    chain(['shF', 'elF', 'haF'], far);
    if (front) {
      canvas.drawLine(P(j['shN']), P(j['shF']), body..strokeWidth = limbW * 1.3);
      canvas.drawLine(P(j['hpN']), P(j['hpF']), body);
      body.strokeWidth = limbW * 1.7;
    }
    canvas.drawLine(P(j['hip']), P(j['neck']), body);
    final head = P(j['head']);
    canvas.drawLine(P(j['neck']), Offset.lerp(P(j['neck']), head, 0.4)!, near);
    canvas.drawCircle(head, Body.headR * s, Paint()..color = C.figure);
    if (!front) {
      // kierunek twarzy: kropka „nosa” po stronie, w którą patrzy postać
      final hd = Offset(math.sin(pose.h * math.pi / 180), math.cos(pose.h * math.pi / 180));
      var face = Offset(-hd.dy, hd.dx);
      if (pose.back) face = -face;
      canvas.drawCircle(head + face * (Body.headR * s * 0.75), Body.headR * s * 0.22, Paint()..color = C.accent);
    }
    chain(['hpN', 'knN', 'anN', 'toN'], near);
    chain(['shN', 'elN', 'haN'], near);

    final hold = scene.ex.hold;
    if (hold != null) {
      final hp = Paint()..color = C.accent;
      for (final k in front ? ['haN', 'haF'] : ['haF', 'haN']) {
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
        if (hold == 'kb') break;
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
