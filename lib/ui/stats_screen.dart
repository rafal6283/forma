import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:rodzina_wykresy/rodzina_wykresy.dart' show InteractiveBarChart, BarItem, CalendarHeatmap, InteractiveLineChart, LineSeries, ChartPoint;

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
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
          child: InteractiveBarChart(
            key: ValueKey(weeks),
            height: 170,
            color: C.accent,
            format: (v) => '${v.round()} min',
            bars: [
              for (final b in buckets)
                BarItem(b.$1, b.$2, detail: '${yearly ? b.$1 : 'tydzień od ${b.$1}'}: ${b.$2.round()} min'),
            ],
          ),
        ),
      ),
      const SectionTitle('Kalendarz treningów'),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: CalendarHeatmap(
            values: () {
              final m = <DateTime, double>{};
              for (final x in s.sessions) {
                final d = DateTime(x.start.year, x.start.month, x.start.day);
                m[d] = (m[d] ?? 0) + x.duration.inMinutes;
              }
              return m;
            }(),
            color: C.accent,
            weeks: yearly ? 26 : 16,
            format: (v) => '${v.round()} min treningu',
            marker: (_, v) => v >= 30,
          ),
        ),
      ),
      SectionTitle('Serie w tym tygodniu', trailing: Text('cel $target na partię', style: TextStyle(color: C.muted, fontSize: 12))),
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
              Text('Gotowość przed treningiem', style: TextStyle(color: C.muted)),
              _trend('Gotowość', [for (final x in list) if (x.readiness > 0) ChartPoint(x.start, x.readiness.toDouble())], C.good, (v) => '${v.round()}'),
              if (list.where((x) => x.avgHr != null).length >= 3) ...[
                const SizedBox(height: 12),
                Text('Średnie tętno na treningu', style: TextStyle(color: C.muted)),
                _trend('Tętno', [for (final x in list) if (x.avgHr != null) ChartPoint(x.start, x.avgHr!.toDouble())], C.bad, (v) => '${v.round()}/min'),
              ],
              if (list.where((x) => x.hrr != null).length >= 2) ...[
                const SizedBox(height: 12),
                Text('Regeneracja tętna po treningu (spadek w minutę)', style: TextStyle(color: C.muted)),
                _trend('Spadek', [for (final x in list) if (x.hrr != null) ChartPoint(x.start, x.hrr!.toDouble())], C.good, (v) => '−${v.round()}/min'),
              ],
              if (s.hrv.length >= 3) ...[
                const SizedBox(height: 12),
                Text('HRV rano (ms)', style: TextStyle(color: C.muted)),
                _trend('HRV', [for (final h in s.hrv.where((h) => !h.at.isBefore(from))) ChartPoint(h.at, h.rmssd)], C.calm, (v) => '${v.round()} ms'),
              ],
              const SizedBox(height: 6),
              Text('Przesuń palcem po wykresie, żeby zobaczyć wartość z danego dnia.', style: TextStyle(color: C.muted, fontSize: 11.5)),
            ]),
          ),
        ),
      ],
      const SectionTitle('Rekordy'),
      _Records(sessions: s.sessions),
    ]);
  }
}

/// Mały interaktywny wykres trendu (rysuje się przy pokazaniu, dymek pod palcem).
Widget _trend(String name, List<ChartPoint> pts, Color color, String Function(double) fmt) {
  final sorted = [...pts]..sort((a, b) => a.x.compareTo(b.x));
  if (sorted.length < 2) return const SizedBox(height: 8);
  return InteractiveLineChart(
    height: 110,
    series: [LineSeries(name, color, sorted, area: true, dots: sorted.length <= 20)],
    yFormat: fmt,
    xFormat: (d) => '${d.day}.${d.month.toString().padLeft(2, '0')}',
  );
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
      return Padding(
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
            subtitle: Text(fmtDate(e.value.$3), style: TextStyle(color: C.muted)),
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
        Text(usesReps ? 'Najlepsza seria (powtórzenia)' : 'Najdłużej (sekundy)', style: TextStyle(color: C.muted)),
        const SizedBox(height: 8),
        if (values.length >= 2)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _trend(usesReps ? 'Powtórzenia' : 'Czas',
                  [for (var i = 0; i < rows.length; i++) ChartPoint(rows[i].$1.start, values[i])], C.accent,
                  (v) => usesReps ? '${v.round()} powt.' : '${v.round()} s'),
            ),
          )
        else
          Text('Wykres pojawi się po drugim treningu z tym ćwiczeniem.', style: TextStyle(color: C.muted)),
        const SectionTitle('Treningi'),
        Card(
          child: Column(children: [
            for (final r in rows.reversed)
              ListTile(
                dense: true,
                title: Text(fmtDate(r.$1.start)),
                subtitle: Text(r.$1.title, style: TextStyle(color: C.muted)),
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
