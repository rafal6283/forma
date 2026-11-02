import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/library.dart';
import '../core/models.dart';
import 'theme.dart';

/// Kształty mapy mięśni (generowane przez tool/muscle_map.py).
class MuscleShapes {
  MuscleShapes._(this.front, this.back, this.outline, this.head, this.headR);
  static MuscleShapes? _i;
  static MuscleShapes? get instance => _i;

  final Map<String, List<Offset>> front, back, outline;
  final Offset head;
  final double headR;

  static Future<void> load() async {
    final j = jsonDecode(await rootBundle.loadString('assets/muscles.json')) as Map<String, dynamic>;
    Map<String, List<Offset>> pts(Map m) => m.map((k, v) => MapEntry(
          k as String,
          (v as List).map((p) => Offset(((p as List)[0] as num).toDouble(), (p[1] as num).toDouble())).toList(),
        ));
    final o = (j['outline'] as Map).cast<String, dynamic>();
    final head = (o.remove('head') as Map).cast<String, dynamic>();
    final c = head['c'] as List;
    _i = MuscleShapes._(
      pts(j['front'] as Map),
      pts(j['back'] as Map),
      pts(o),
      Offset((c[0] as num).toDouble(), (c[1] as num).toDouble()),
      (head['r'] as num).toDouble(),
    );
  }
}

/// Obciążenie mięśni (0..1) z wykonanych ćwiczeń: sekundy × udział mięśnia, rozciąganie liczy się słabiej.
Map<String, double> muscleLoad(Iterable<DoneItem> done, {double Function(DoneItem)? weight}) {
  final lib = Library.instance;
  final out = <String, double>{};
  for (final d in done) {
    final e = lib[d.exId];
    if (e == null) continue;
    final f = switch (e.type) {
          ExType.stretch => 0.25,
          ExType.mobility || ExType.warmup => 0.4,
          _ => 1.0,
        } *
        (weight?.call(d) ?? 1.0);
    e.muscles.forEach((m, w) => out[m] = (out[m] ?? 0) + d.seconds * w * f);
  }
  final mx = out.values.fold(0.0, math.max);
  if (mx <= 0) return {};
  return out.map((k, v) => MapEntry(k, v / mx));
}

/// Mięśnie ćwiczenia: główne = 1, pomocnicze = 0,5.
Map<String, double> exerciseLoad(Exercise e) => e.muscles;

/// Sylwetka przód + tył z podświetlonymi mięśniami.
class MuscleMap extends StatelessWidget {
  final Map<String, double> load;
  final double height;
  final bool legend;
  const MuscleMap(this.load, {super.key, this.height = 220, this.legend = true});

  @override
  Widget build(BuildContext context) {
    final shapes = MuscleShapes.instance;
    if (shapes == null) return SizedBox(height: height);
    final top = load.entries.where((e) => e.value >= 0.15).toList()..sort((a, b) => b.value.compareTo(a.value));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: height,
        child: Row(children: [
          Expanded(child: _Side(shapes, front: true, load: load, label: 'Przód')),
          Expanded(child: _Side(shapes, front: false, load: load, label: 'Tył')),
        ]),
      ),
      if (legend && top.isNotEmpty) ...[
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final e in top.take(8))
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: muscleColor(e.value).withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
              child: Text(muscleLabel[e.key] ?? e.key, style: TextStyle(color: muscleColor(e.value), fontSize: 12, fontWeight: FontWeight.w600)),
            ),
        ]),
      ],
    ]);
  }
}

Color muscleColor(double v) {
  if (v <= 0) return C.surface2;
  final t = v.clamp(0.0, 1.0);
  return Color.lerp(const Color(0xFF8A6A3A), C.accent, t)!.withValues(alpha: 0.55 + 0.45 * t);
}

class _Side extends StatelessWidget {
  final MuscleShapes shapes;
  final bool front;
  final Map<String, double> load;
  final String label;
  const _Side(this.shapes, {required this.front, required this.load, required this.label});

  @override
  Widget build(BuildContext context) => Column(children: [
        Expanded(child: CustomPaint(painter: _MapPainter(shapes, front, load), size: Size.infinite)),
        Text(label, style: TextStyle(color: C.muted, fontSize: 11)),
      ]);
}

class _MapPainter extends CustomPainter {
  final MuscleShapes s;
  final bool front;
  final Map<String, double> load;
  _MapPainter(this.s, this.front, this.load);

  @override
  void paint(Canvas canvas, Size size) {
    const w = 100.0, h = 220.0;
    final k = math.min(size.width / w, size.height / h);
    final dx = (size.width - w * k) / 2;
    Offset P(Offset p) => Offset(dx + p.dx * k, p.dy * k);
    List<Offset> mirror(List<Offset> pts) => pts.reversed.map((p) => Offset(100 - p.dx, p.dy)).toList();

    final base = Paint()..color = C.surface2;
    final gap = Paint()
      ..color = C.surface
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, k * 0.8)
      ..strokeJoin = StrokeJoin.round;

    void poly(List<Offset> pts, Paint fill) {
      final path = Path()..addPolygon(pts.map(P).toList(), true);
      canvas.drawPath(path, fill);
      canvas.drawPath(path, gap);
    }

    canvas.drawCircle(P(s.head), s.headR * k, base);
    s.outline.forEach((name, pts) {
      if (name == 'pelvis_f' && !front) return;
      poly(pts, base);
      poly(mirror(pts), base);
    });
    final regions = front ? s.front : s.back;
    regions.forEach((name, pts) {
      final v = load[name] ?? 0;
      final p = Paint()..color = muscleColor(v);
      poly(pts, p);
      poly(mirror(pts), p);
    });
  }

  @override
  bool shouldRepaint(_MapPainter o) => o.load != load || o.front != front;
}
