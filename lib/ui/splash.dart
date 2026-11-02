import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// Ekran startowy: logo Formy „wskakuje”, pierścień tętna się rozchodzi, napis wjeżdża.
class SplashScreen extends StatefulWidget {
  final VoidCallback onDone;
  const SplashScreen({super.key, required this.onDone});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))
    ..forward().whenComplete(() {
      if (mounted) widget.onDone();
    });

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: C.bg,
        body: GestureDetector(
          onTap: widget.onDone,
          child: Center(
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, __) {
                final t = _c.value;
                final pop = Curves.elasticOut.transform((t / 0.6).clamp(0, 1));
                final ring = Curves.easeOut.transform(((t - 0.15) / 0.6).clamp(0, 1));
                final txt = Curves.easeOutCubic.transform(((t - 0.35) / 0.45).clamp(0, 1));
                return Column(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(
                    width: 180,
                    height: 180,
                    child: CustomPaint(
                      painter: _LogoPainter(pop, ring),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Opacity(
                    opacity: txt,
                    child: Transform.translate(
                      offset: Offset(0, 16 * (1 - txt)),
                      child: Column(children: [
                        Text('Forma',
                            style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: 1.5, color: C.text)),
                        const SizedBox(height: 4),
                        Text('Twój trener w domu', style: TextStyle(color: C.muted)),
                      ]),
                    ),
                  ),
                ]);
              },
            ),
          ),
        ),
      );
}

class _LogoPainter extends CustomPainter {
  final double pop, ring;
  _LogoPainter(this.pop, this.ring);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width * 0.3;
    // rozchodzący się pierścień (puls)
    if (ring > 0 && ring < 1) {
      canvas.drawCircle(
        c,
        r * (1 + ring * 0.9),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6 * (1 - ring)
          ..color = C.accent.withValues(alpha: 0.6 * (1 - ring)),
      );
    }
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(pop.clamp(0.0, 1.2));
    final rect = RRect.fromRectAndRadius(Rect.fromCircle(center: Offset.zero, radius: r), Radius.circular(r * 0.42));
    canvas.drawRRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF8A5C), C.accent, Color(0xFFE2462A)],
        ).createShader(rect.outerRect),
    );
    // linia tętna przez logo
    final p = Path()
      ..moveTo(-r * 0.75, 0)
      ..lineTo(-r * 0.3, 0)
      ..lineTo(-r * 0.15, -r * 0.42)
      ..lineTo(r * 0.05, r * 0.45)
      ..lineTo(r * 0.22, -r * 0.18)
      ..lineTo(r * 0.32, 0)
      ..lineTo(r * 0.75, 0);
    final m = p.computeMetrics().first;
    canvas.drawPath(
      m.extractPath(0, m.length * pop.clamp(0.0, 1.0)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.12
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white,
    );
    canvas.restore();
    // drobne iskry
    final rnd = math.Random(3);
    for (var i = 0; i < 10; i++) {
      final a = rnd.nextDouble() * math.pi * 2;
      final d = r * (1.1 + ring * (0.6 + rnd.nextDouble() * 0.5));
      canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * d, 2.5 * (1 - ring),
          Paint()..color = C.accent.withValues(alpha: 1 - ring));
    }
  }

  @override
  bool shouldRepaint(_LogoPainter old) => old.pop != pop || old.ring != ring;
}
