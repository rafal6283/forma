import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/store.dart';
import '../core/trainer.dart';
import 'theme.dart';
import 'widgets.dart';

/// Wykres tętna z treningu, kolorowany strefami.
class HrChart extends StatelessWidget {
  final Session session;
  const HrChart(this.session, {super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 140,
        child: CustomPaint(painter: _HrPainter(session.hr, Store.instance.profile.maxHr), size: Size.infinite),
      );
}

class _HrPainter extends CustomPainter {
  final List<int> hr;
  final int maxHr;
  _HrPainter(this.hr, this.maxHr);

  @override
  void paint(Canvas canvas, Size size) {
    final vals = hr.where((v) => v > 0).toList();
    if (vals.length < 2) return;
    final lo = (vals.reduce(math.min) - 5).toDouble();
    final hi = (vals.reduce(math.max) + 5).toDouble();
    double y(num v) => size.height - (v - lo) / (hi - lo) * size.height;
    // linie stref
    for (final p in [0.6, 0.7, 0.8, 0.9]) {
      final v = maxHr * p;
      if (v <= lo || v >= hi) continue;
      canvas.drawLine(
        Offset(0, y(v)),
        Offset(size.width, y(v)),
        Paint()
          ..color = C.line
          ..strokeWidth = 1,
      );
    }
    final dx = size.width / (hr.length - 1);
    for (var i = 1; i < hr.length; i++) {
      final a = hr[i - 1], b = hr[i];
      if (a <= 0 || b <= 0) continue;
      canvas.drawLine(
        Offset((i - 1) * dx, y(a)),
        Offset(i * dx, y(b)),
        Paint()
          ..color = C.zone(Trainer.zone(b, maxHr))
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_HrPainter o) => o.hr != hr;
}

/// Czas w strefach tętna.
class ZonesBar extends StatelessWidget {
  final List<int> zones;
  const ZonesBar(this.zones, {super.key});

  @override
  Widget build(BuildContext context) {
    final total = zones.fold(0, (a, b) => a + b);
    if (total == 0) return const SizedBox();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Row(children: [
          for (var i = 0; i < 5; i++)
            if (zones[i] > 0) Expanded(flex: zones[i], child: Container(height: 12, color: C.zones[i])),
        ]),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 12, runSpacing: 4, children: [
        for (var i = 0; i < 5; i++)
          if (zones[i] > 0)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: C.zones[i], shape: BoxShape.circle)),
              const SizedBox(width: 4),
              Text('S${i + 1} ${fmtDur(zones[i])}', style: const TextStyle(color: C.muted, fontSize: 12)),
            ]),
      ]),
    ]);
  }
}

/// Liczby z sesji.
class SessionStats extends StatelessWidget {
  final Session s;
  const SessionStats(this.s, {super.key});

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: Stat('czas', fmtDur(s.duration.inSeconds))),
        Expanded(child: Stat('kcal', '${s.kcal.round()}')),
        Expanded(child: Stat('śr. tętno', s.avgHr?.toString() ?? '–')),
        Expanded(child: Stat('maks.', s.maxHr?.toString() ?? '–')),
      ]);
}
