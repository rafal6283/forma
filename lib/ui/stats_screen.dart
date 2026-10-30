import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/coach.dart';
import '../core/library.dart';
import '../core/models.dart';
import '../core/store.dart';
import 'exercise_screen.dart';
import 'session_widgets.dart';
import 'theme.dart';
import 'widgets.dart';

DateTime _monday(DateTime d) => DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));

/// Przegląd postępów: liczby, tygodnie, kalendarz, serie na partię, strefy, trendy, rekordy.
class StatsView extends StatefulWidget {
  const StatsView({super.key});

  @override
  State<StatsView> createState() => _StatsViewState();
}

class _StatsViewState extends State<StatsView> {
  int weeks = 12;

  @override
  Widget build(BuildContext context) {
    final s = Store.instance;
    final now = DateTime.now();
    final from = _monday(now).subtract(Duration(days: 7 * (weeks - 1)));
    final list = s.sessions.where((x) => !x.start.isBefore(from)).toList();
    final lib = Library.instance;

    final secs = list.fold(0, (a, x) => a + x.duration.inSeconds);
    final kcal = list.fold(0.0, (a, x) => a + x.kcal);
    final rpe = list.isEmpty ? 0.0 : list.fold(0, (a, x) => a + x.rpe) / list.length;
    var sets = 0, reps = 0;
    final zones = [0, 0, 0, 0, 0];
    final formats = <WorkoutFormat, int>{};
    for (final x in list) {
      formats[x.format] = (formats[x.format] ?? 0) + 1;
      for (var i = 0; i < 5 && i < x.zones.length; i++) {
        zones[i] += x.zones[i];
      }
      for (final d in x.done) {
        final e = lib[d.exId];
        if (e == null || d.side == 2) continue;
        if ({ExType.strength, ExType.core, ExType.cardio}.contains(e.type)) sets++;
        reps += d.reps ?? 0;
      }
    }

    // minuty w kolejnych tygodniach (albo miesiącach przy roku)
    final yearly = weeks > 20;
    final buckets = <(String, double)>[];
    if (yearly) {
      for (var m = 11; m >= 0; m--) {
        final d = DateTime(now.year, now.month - m, 1);
        final e = DateTime(d.year, d.month + 1, 1);
        final mins = s.sessions.where((x) => !x.start.isBefore(d) && x.start.isBefore(e)).fold(0, (a, x) => a + x.duration.inMinutes);
        buckets.add((const ['sty', 'lut', 'mar', 'kwi', 'maj', 'cze', 'lip', 'sie', 'wrz', 'paź', 'lis', 'gru'][d.month - 1], mins.toDouble()));
      }
    } else {
      for (var w = weeks - 1; w >= 0; w--) {
        final d = _monday(now).subtract(Duration(days: 7 * w));
        final e = d.add(const Duration(days: 7));
        final mins = s.sessions.where((x) => !x.start.isBefore(d) && x.start.isBefore(e)).fold(0, (a, x) => a + x.duration.inMinutes);
        buckets.add(('${d.day}.${d.month}', mins.toDouble()));
      }
    }

    final t = coach();
    final week = t.weeklySets();
    final target = t.weeklySetTarget;

    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
      Wrap(spacing: 8, children: [
        for (final w in [4, 12, 52])
          ChoiceChip(
            label: Text(w == 52 ? 'Rok' : '$w tyg.'),
            selected: weeks == w,
            onSelected: (_) => setState(() => weeks = w),
          ),
      ]),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Row(children: [
              Expanded(child: Stat('treningi', '${list.length}')),
              Expanded(child: Stat('czas', fmtMin(secs))),
              Expanded(child: Stat('kcal', '${kcal.round()}')),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: Stat('serie', '$sets')),
              Expanded(child: Stat('powtórzenia', '$reps')),
              Expanded(child: Stat('śr. RPE', list.isEmpty ? '–' : rpe.toStringAsFixed(1).replaceAll('.', ','))),
            ]),
          ]),
        ),
      ),
      SectionTitle(yearly ? 'Minuty w miesiącach' : 'Minuty w tygodniach'),
      Card(
        child: Padding(padding: const EdgeInsets.fromLTRB(12, 16, 12, 8), child: SizedBox(height: 150, child: _Bars(buckets))),
      ),
      const SectionTitle('Kalendarz (12 tygodni)'),
      Card(child: Padding(padding: const EdgeInsets.all(14), child: _Heatmap(s.sessions))),
      SectionTitle('Serie w tym tygodniu', trailing: Text('cel $target na partię', style: const TextStyle(color: C.muted, fontSize: 12))),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            for (final g in muscleGroups)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  SizedBox(width: 72, child: Text(g)),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: ((week[g] ?? 0) / target).clamp(0, 1).toDouble(),
                        minHeight: 10,
                        backgroundColor: C.surface2,
                        color: (week[g] ?? 0) >= target ? C.good : C.accent,
                      ),
                    ),
                  ),
                  SizedBox(width: 36, child: Text('${week[g] ?? 0}', textAlign: TextAlign.right)),
                ]),
              ),
          ]),
        ),
      ),
      if (formats.isNotEmpty) ...[
        const SectionTitle('Formaty'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in formats.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
            Chip(label: Text('${formatLabel[e.key]} · ${e.value}')),
        ]),
      ],
      if (zones.any((z) => z > 0)) ...[
        const SectionTitle('Strefy tętna'),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: ZonesBar(zones))),
      ],
      if (list.length >= 3) ...[
        const SectionTitle('Trendy'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Gotowość przed treningiem', style: TextStyle(color: C.muted)),
              SizedBox(height: 70, child: _Line([for (final x in list) if (x.readiness > 0) x.readiness.toDouble()], C.good)),
              if (list.where((x) => x.avgHr != null).length >= 3) ...[
                const SizedBox(height: 12),
                const Text('Średnie tętno na treningu', style: TextStyle(color: C.muted)),
                SizedBox(height: 70, child: _Line([for (final x in list) if (x.avgHr != null) x.avgHr!.toDouble()], C.bad)),
              ],
              if (list.where((x) => x.hrr != null).length >= 2) ...[
                const SizedBox(height: 12),
                const Text('Regeneracja tętna po treningu (spadek w minutę)', style: TextStyle(color: C.muted)),
                SizedBox(height: 70, child: _Line([for (final x in list) if (x.hrr != null) x.hrr!.toDouble()], C.good)),
              ],
              if (s.hrv.length >= 3) ...[
                const SizedBox(height: 12),
                const Text('HRV rano (ms)', style: TextStyle(color: C.muted)),
                SizedBox(height: 70, child: _Line([for (final h in s.hrv.where((h) => !h.at.isBefore(from))) h.rmssd], C.calm)),
              ],
            ]),
          ),
        ),
      ],
      const SectionTitle('Rekordy'),
      _Records(sessions: s.sessions),
    ]);
  }
}

class _Bars extends StatelessWidget {
  final List<(String, double)> data;
  const _Bars(this.data);

  @override
  Widget build(BuildContext context) {
    final mx = data.fold(0.0, (a, b) => math.max(a, b.$2));
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      for (var i = 0; i < data.length; i++)
        Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
            if (data[i].$2 > 0)
              Text('${data[i].$2.round()}', style: const TextStyle(fontSize: 9, color: C.muted)),
            Container(
              height: mx == 0 ? 2 : math.max(2, data[i].$2 / mx * 100),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: i == data.length - 1 ? C.accent : C.accent.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 4),
            Text(i % (data.length > 8 ? 2 : 1) == 0 ? data[i].$1 : '',
                style: const TextStyle(fontSize: 9, color: C.muted), maxLines: 1),
          ]),
        ),
    ]);
  }
}

/// Kalendarz aktywności: 12 tygodni × 7 dni, kolor wg minut.
class _Heatmap extends StatelessWidget {
  final List<Session> sessions;
  const _Heatmap(this.sessions);

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final start = _monday(now).subtract(const Duration(days: 7 * 11));
    final mins = <String, int>{};
    for (final s in sessions) {
      final k = '${s.start.year}-${s.start.month}-${s.start.day}';
      mins[k] = (mins[k] ?? 0) + s.duration.inMinutes;
    }
    Color c(int m) => m == 0
        ? C.surface2
        : m < 15
            ? C.accent.withValues(alpha: 0.35)
            : m < 30
                ? C.accent.withValues(alpha: 0.65)
                : C.accent;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Column(children: [
        for (final d in const ['P', 'W', 'Ś', 'C', 'P', 'S', 'N'])
          SizedBox(height: 18, child: Text(d, style: const TextStyle(fontSize: 10, color: C.muted))),
      ]),
      const SizedBox(width: 6),
      for (var w = 0; w < 12; w++)
        Expanded(
          child: Column(children: [
            for (var d = 0; d < 7; d++)
              Builder(builder: (_) {
                final day = start.add(Duration(days: w * 7 + d));
                final future = day.isAfter(now);
                final m = mins['${day.year}-${day.month}-${day.day}'] ?? 0;
                return Container(
                  height: 14,
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: future ? Colors.transparent : c(m),
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
          ]),
        ),
    ]);
  }
}

class _Line extends StatelessWidget {
  final List<double> v;
  final Color color;
  const _Line(this.v, this.color);

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _LinePainter(v, color), size: Size.infinite);
}

class _LinePainter extends CustomPainter {
  final List<double> v;
  final Color c;
  _LinePainter(this.v, this.c);

  @override
  void paint(Canvas canvas, Size size) {
    if (v.length < 2) return;
    var lo = v.reduce(math.min), hi = v.reduce(math.max);
    if (hi - lo < 1) {
      lo -= 1;
      hi += 1;
    }
    final dx = size.width / (v.length - 1);
    Offset p(int i) => Offset(i * dx, size.height - 4 - (v[i] - lo) / (hi - lo) * (size.height - 8));
    final path = Path()..moveTo(p(0).dx, p(0).dy);
    for (var i = 1; i < v.length; i++) {
      path.lineTo(p(i).dx, p(i).dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = c
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );
    final tp = TextPainter(
      text: TextSpan(text: '${v.last.round()}', style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w700)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(size.width - tp.width, 0));
  }

  @override
  bool shouldRepaint(_LinePainter o) => o.v != v;
}

/// Najlepsze wyniki w ćwiczeniach: najwięcej powtórzeń w serii albo najdłuższe utrzymanie.
class _Records extends StatelessWidget {
  final List<Session> sessions;
  const _Records({required this.sessions});

  @override
  Widget build(BuildContext context) {
    final lib = Library.instance;
    final best = <String, (int, bool, DateTime)>{}; // id → (wynik, powtórzenia?, kiedy)
    for (final s in sessions) {
      for (final d in s.done) {
        final e = lib[d.exId];
        if (e == null || e.type == ExType.warmup || e.type == ExType.stretch) continue;
        final isReps = d.reps != null;
        if (!isReps && !e.isStatic) continue;
        final v = d.reps ?? d.seconds;
        final cur = best[d.exId];
        if (cur == null || v > cur.$1) best[d.exId] = (v, isReps, s.start);
      }
    }
    if (best.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Text('Rekordy pojawią się po treningach z seriami na powtórzenia i ćwiczeniach na czas (np. deska).',
            style: TextStyle(color: C.muted)),
      );
    }
    final entries = best.entries.toList()..sort((a, b) => b.value.$3.compareTo(a.value.$3));
    return Card(
      child: Column(children: [
        for (final e in entries.take(15))
          ListTile(
            dense: true,
            title: Text(lib[e.key]?.name ?? e.key),
            subtitle: Text(fmtDate(e.value.$3), style: const TextStyle(color: C.muted)),
            trailing: Text(e.value.$2 ? '${e.value.$1} powt.' : fmtDur(e.value.$1),
                style: const TextStyle(fontWeight: FontWeight.w800, color: C.accent)),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ExerciseProgressScreen(exId: e.key)),
            ),
          ),
      ]),
    );
  }
}

/// Postęp w jednym ćwiczeniu: najlepsza seria w kolejnych treningach.
class ExerciseProgressScreen extends StatelessWidget {
  final String exId;
  const ExerciseProgressScreen({super.key, required this.exId});

  @override
  Widget build(BuildContext context) {
    final e = Library.instance[exId];
    final rows = <(Session, List<DoneItem>)>[];
    for (final s in Store.instance.sessions) {
      final l = s.done.where((d) => d.exId == exId && d.side != 2).toList();
      if (l.isNotEmpty) rows.add((s, l));
    }
    final usesReps = rows.any((r) => r.$2.any((d) => d.reps != null));
    final values = [
      for (final r in rows) (usesReps ? r.$2.map((d) => d.reps ?? 0) : r.$2.map((d) => d.seconds)).reduce(math.max).toDouble(),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(e?.name ?? exId), actions: [
        if (e != null)
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ExerciseScreen(exercise: e))),
          ),
      ]),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
        Text(usesReps ? 'Najlepsza seria (powtórzenia)' : 'Najdłużej (sekundy)', style: const TextStyle(color: C.muted)),
        const SizedBox(height: 8),
        if (values.length >= 2)
          Card(child: Padding(padding: const EdgeInsets.all(16), child: SizedBox(height: 140, child: _Line(values, C.accent))))
        else
          const Text('Wykres pojawi się po drugim treningu z tym ćwiczeniem.', style: TextStyle(color: C.muted)),
        const SectionTitle('Treningi'),
        Card(
          child: Column(children: [
            for (final r in rows.reversed)
              ListTile(
                dense: true,
                title: Text(fmtDate(r.$1.start)),
                subtitle: Text(r.$1.title, style: const TextStyle(color: C.muted)),
                trailing: Text(
                  r.$2.map((d) => d.reps != null ? '${d.reps}' : fmtDur(d.seconds)).join(' / '),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}
