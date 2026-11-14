import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../core/coach.dart';
import '../core/command.dart';
import '../core/models.dart';
import '../core/store.dart';
import 'preview_screen.dart';
import 'theme.dart';
import 'widgets.dart';

String _kg(double w) => w.toStringAsFixed(w >= 20 ? 0 : 1).replaceAll('.', ',');

/// Prosty wykres liniowy (bez osi) — trend wartości.
class TrendLine extends StatelessWidget {
  final List<double> values;
  final Color color;
  final double height;
  const TrendLine(this.values, {super.key, this.color = C.accent, this.height = 60});

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: height, width: double.infinity, child: CustomPaint(painter: _TrendPainter(values, color)));
}

class _TrendPainter extends CustomPainter {
  final List<double> v;
  final Color color;
  _TrendPainter(this.v, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (v.length < 2) return;
    final lo = v.reduce(math.min), hi = v.reduce(math.max);
    final span = math.max(1e-6, hi - lo);
    Offset at(int i) =>
        Offset(size.width * i / (v.length - 1), size.height - 6 - (v[i] - lo) / span * (size.height - 12));
    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < v.length; i++) {
      path.lineTo(at(i).dx, at(i).dy);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round);
    for (var i = 0; i < v.length; i++) {
      canvas.drawCircle(at(i), 3, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_TrendPainter o) => o.v != v;
}

/// Szacowany maksymalny ciężar w ćwiczeniu z hantlami/kettlem i jego trend.
class StrengthCard extends StatelessWidget {
  final Exercise exercise;
  const StrengthCard(this.exercise, {super.key});

  @override
  Widget build(BuildContext context) {
    if (!exercise.weighted) return const SizedBox.shrink();
    final pts = coach().oneRepMax(exercise.id);
    if (pts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text('Wpisuj ciężar podczas serii — pokażę szacowany maksymalny ciężar i jego wzrost.',
            style: TextStyle(color: C.muted, fontSize: 13)),
      );
    }
    final last = pts.last.$2, first = pts.first.$2;
    final d = last - first;
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.fitness_center, size: 18, color: C.accent),
            const SizedBox(width: 8),
            Expanded(
                child: Text('Szacowany max (1 powt.): ${_kg(last)} kg',
                    style: const TextStyle(fontWeight: FontWeight.w800))),
            if (pts.length > 1)
              Text('${d >= 0 ? '+' : ''}${_kg(d)} kg',
                  style: TextStyle(color: d >= 0 ? C.good : C.warn, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 8),
          if (pts.length > 1) TrendLine([for (final p in pts.length > 20 ? pts.sublist(pts.length - 20) : pts) p.$2]),
          Text('Z ciężaru i powtórzeń najlepszej serii (wzór Epleya). Do porównań, nie do testowania maksa.',
              style: TextStyle(color: C.muted, fontSize: 11)),
        ]),
      ),
    );
  }
}

/// Bilans partii z 4 tygodni: pchanie/ciągnięcie, przód/tył uda.
class BalanceCard extends StatelessWidget {
  const BalanceCard({super.key});

  Widget _bar(String a, int va, String b, int vb) {
    final sum = math.max(1, va + vb);
    final ratio = va / sum;
    final ok = (ratio - 0.5).abs() < 0.12;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(children: [
        Row(children: [
          Expanded(child: Text('$a · $va', style: const TextStyle(fontSize: 13))),
          Text('$vb · $b', style: const TextStyle(fontSize: 13)),
        ]),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 10,
            child: Row(children: [
              Expanded(flex: math.max(1, (ratio * 100).round()), child: Container(color: ok ? C.good : C.warn)),
              Expanded(flex: math.max(1, 100 - (ratio * 100).round()), child: Container(color: C.calm)),
            ]),
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = coach().balance();
    if (b.push + b.pull + b.quad + b.posterior < 6) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionTitle('Bilans partii (4 tygodnie, serie)'),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _bar('Pchanie', b.push, 'Ciągnięcie', b.pull),
            _bar('Przód uda', b.quad, 'Tył uda i pośladki', b.posterior),
            const SizedBox(height: 6),
            Text(b.note ?? 'Proporcje w porządku — trener utrzymuje równowagę.',
                style: TextStyle(color: C.muted, fontSize: 13, height: 1.35)),
          ]),
        ),
      ),
    ]);
  }
}

/// Polecenie zwykłym zdaniem (wpisane lub powiedziane) → gotowy plan.
Future<void> showCommandSheet(BuildContext context) async {
  final plan = await showModalBottomSheet<WorkoutPlan>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _CommandSheet(),
  );
  if (plan != null && context.mounted) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => PreviewScreen(plan: plan)));
  }
}

class _CommandSheet extends StatefulWidget {
  const _CommandSheet();

  @override
  State<_CommandSheet> createState() => _CommandSheetState();
}

class _CommandSheetState extends State<_CommandSheet> {
  final ctl = TextEditingController();
  final stt = SpeechToText();
  bool listening = false;
  WorkoutCommand cmd = const WorkoutCommand();

  static const examples = [
    '20 minut na brzuch, bez skakania',
    'lekko 15 minut rozciągania',
    'mocno nogi z hantlami 30 min',
    'tabata cicho 12 minut',
  ];

  void _parse() => setState(() => cmd = parseCommand(ctl.text, Store.instance.profile.equipment));

  Future<void> _listen() async {
    if (listening) {
      await stt.stop();
      setState(() => listening = false);
      return;
    }
    final ok = await stt.initialize();
    if (!ok) {
      if (mounted) toast(context, 'Rozpoznawanie mowy niedostępne');
      return;
    }
    setState(() => listening = true);
    await stt.listen(
      localeId: 'pl_PL',
      onResult: (r) {
        ctl.text = r.recognizedWords;
        _parse();
        if (r.finalResult && mounted) setState(() => listening = false);
      },
    );
  }

  @override
  void dispose() {
    stt.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Jaki trening?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          TextField(
            controller: ctl,
            autofocus: true,
            textInputAction: TextInputAction.go,
            onChanged: (_) => _parse(),
            onSubmitted: (_) => cmd.isEmpty ? null : Navigator.pop(context, planFromCommand(cmd)),
            decoration: InputDecoration(
              hintText: 'np. 20 minut na brzuch, bez skakania',
              suffixIcon: IconButton(
                tooltip: 'Powiedz',
                icon: Icon(listening ? Icons.mic : Icons.mic_none, color: listening ? C.accent : null),
                onPressed: _listen,
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (cmd.isEmpty)
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final e in examples)
                ActionChip(
                  label: Text(e, style: const TextStyle(fontSize: 12)),
                  onPressed: () {
                    ctl.text = e;
                    _parse();
                  },
                ),
            ])
          else
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final u in cmd.understood)
                Chip(avatar: const Icon(Icons.check, size: 16, color: C.good), label: Text(u)),
            ]),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: cmd.isEmpty ? null : () => Navigator.pop(context, planFromCommand(cmd)),
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Ułóż trening'),
          ),
        ]),
      );
}

/// Bilans dnia: zjedzone (Dziennik talerza) i spalone na treningach.
class EnergyCard extends StatelessWidget {
  const EnergyCard({super.key});

  @override
  Widget build(BuildContext context) {
    final s = Store.instance;
    final now = DateTime.now();
    final meals = s.dayFactors.meals(now);
    if (meals == null) return const SizedBox.shrink();
    bool same(DateTime d) => d.year == now.year && d.month == now.month && d.day == now.day;
    final burned = s.sessions.where((x) => same(x.start)).fold(0.0, (a, x) => a + x.kcal).round();
    final eaten = ((meals['kcal'] as num?) ?? 0).round();
    final strength = s.sessions.any((x) => same(x.start) && x.kind != WorkoutKind.mobility && x.kind != WorkoutKind.stretch);
    final w = s.profile.weightKg;
    final protein = (w * (strength ? 1.6 : 1.2)).round();
    return Card(
      child: ListTile(
        leading: const CircleAvatar(backgroundColor: Color(0x3346C2A0), child: Icon(Icons.restaurant, color: C.good)),
        title: Text('Dziś: zjedzone $eaten kcal · trening $burned kcal', style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          '${meals['meals'] ?? 0} posiłków z Dziennika talerza · białko dziś ok. $protein g'
          '${strength ? ' (dzień siłowy)' : ''}',
          style: TextStyle(color: C.muted),
        ),
      ),
    );
  }
}
