import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// Konfetti po ukończonym treningu — jednorazowy wystrzał (ok. 2,5 s), nie blokuje dotyku.
class Confetti extends StatefulWidget {
  const Confetti({super.key});

  @override
  State<Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<Confetti> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))
    ..forward();
  final _bits = List.generate(70, (i) => _Bit(math.Random(i * 7 + 1)));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => _c.isCompleted
              ? const SizedBox.shrink()
              : CustomPaint(painter: _ConfettiPainter(_bits, _c.value), size: Size.infinite),
        ),
      );
}

class _Bit {
  final double x, vx, vy, spin, size;
  final Color color;
  _Bit(math.Random r)
      : x = 0.3 + r.nextDouble() * 0.4,
        vx = (r.nextDouble() - 0.5) * 1.4,
        vy = -(0.9 + r.nextDouble() * 0.9),
        spin = (r.nextDouble() - 0.5) * 18,
        size = 5 + r.nextDouble() * 6,
        color = [C.accent, C.good, C.warn, C.calm, const Color(0xFFB59BFF)][r.nextInt(5)];
}

class _ConfettiPainter extends CustomPainter {
  final List<_Bit> bits;
  final double t;
  _ConfettiPainter(this.bits, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final time = t * 2.6;
    for (final b in bits) {
      // rzut ukośny z grawitacją, start u dołu ekranu
      final x = (b.x + b.vx * time * 0.35) * size.width;
      final y = size.height * (0.85 + b.vy * time * 0.55 + 0.42 * time * time * 0.55);
      final fade = (1 - t).clamp(0.0, 1.0);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(b.spin * time);
      canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: b.size, height: b.size * 0.55),
          Paint()..color = b.color.withValues(alpha: fade));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
