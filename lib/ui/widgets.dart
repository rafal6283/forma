import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/hr.dart';
import '../core/store.dart';
import '../core/trainer.dart';
import 'hr_screen.dart';
import 'theme.dart';

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
        child: Row(children: [
          Expanded(
            child: Text(text.toUpperCase(),
                style: TextStyle(color: C.muted, fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.w700)),
          ),
          if (trailing != null) trailing!,
        ]),
      );
}

class Stat extends StatelessWidget {
  final String label, value;
  final Color? color;
  const Stat(this.label, this.value, {super.key, this.color});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color ?? C.text)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(color: C.muted, fontSize: 12)),
      ]);
}

/// Pierścień postępu z wartością w środku.
class Ring extends StatelessWidget {
  final double value; // 0..1
  final Color color;
  final double size, width;
  final Widget child;
  const Ring({super.key, required this.value, required this.color, required this.child, this.size = 96, this.width = 9});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(value.clamp(0, 1).toDouble(), color, width),
          child: Center(child: child),
        ),
      );
}

class _RingPainter extends CustomPainter {
  final double v;
  final Color c;
  final double w;
  _RingPainter(this.v, this.c, this.w);

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(w / 2, w / 2, size.width - w, size.height - w);
    final bg = Paint()
      ..color = C.surface2
      ..style = PaintingStyle.stroke
      ..strokeWidth = w;
    canvas.drawArc(r, 0, math.pi * 2, false, bg);
    canvas.drawArc(
      r,
      -math.pi / 2,
      math.pi * 2 * v,
      false,
      Paint()
        ..color = c
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.v != v || o.c != c;
}

/// Tętno na żywo / stan opaski; dotknięcie otwiera ekran urządzenia.
class HrBadge extends StatelessWidget {
  final bool large;
  const HrBadge({super.key, this.large = false});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: HrService.instance,
        builder: (context, _) {
          final hr = HrService.instance;
          final p = Store.instance.profile;
          final bpm = hr.freshBpm;
          final z = bpm == null ? null : Trainer.zone(bpm, p.maxHr);
          final color = z == null ? C.muted : C.zone(z);
          final text = switch (hr.state) {
            HrState.connected => bpm == null ? '–' : '$bpm',
            HrState.connecting || HrState.reconnecting => '…',
            _ => p.hrDeviceId == null ? 'Tętno' : 'Połącz',
          };
          return InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HrScreen())),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: large ? 14 : 10, vertical: large ? 8 : 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(hr.connected ? Icons.favorite : Icons.favorite_border, color: color, size: large ? 26 : 18),
                const SizedBox(width: 6),
                Text(text,
                    style: TextStyle(
                        color: hr.connected ? color : C.text,
                        fontWeight: FontWeight.w800,
                        fontSize: large ? 28 : 14)),
                if (z != null && large) ...[
                  const SizedBox(width: 6),
                  Text('S$z', style: TextStyle(color: color, fontWeight: FontWeight.w700)),
                ],
              ]),
            ),
          );
        },
      );
}

class LevelDots extends StatelessWidget {
  final int level;
  const LevelDots(this.level, {super.key});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= 5; i++)
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 3),
              decoration: BoxDecoration(shape: BoxShape.circle, color: i <= level ? C.accent : C.line),
            ),
        ],
      );
}

Future<bool> confirm(BuildContext context, String title, String body, {String ok = 'Tak'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Anuluj')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(ok)),
      ],
    ),
  );
  return r == true;
}

void toast(BuildContext context, String msg) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
