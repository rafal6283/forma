import 'package:flutter/material.dart';

import '../core/coach.dart';
import '../core/hr.dart';
import '../core/library.dart';
import '../core/models.dart';
import '../core/store.dart';
import 'exercise_screen.dart';
import 'figure_view.dart';
import 'player_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Podgląd treningu: ćwiczenia, zamiana, start.
class PreviewScreen extends StatefulWidget {
  final WorkoutPlan plan;
  const PreviewScreen({super.key, required this.plan});

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  late WorkoutPlan plan = widget.plan;
  int _seed = 1;

  @override
  void initState() {
    super.initState();
    final p = Store.instance.profile;
    final hr = HrService.instance;
    if (p.hrDeviceId != null && hr.state == HrState.idle) hr.connectSaved(p.hrDeviceId!, p.hrDeviceName);
  }

  void _swap(String exId) {
    final lib = Library.instance;
    final cur = lib[exId]!;
    final inPlan = plan.items.map((i) => i.exId).toSet();
    final alt = coach().alternative(cur, inPlan, seed: _seed++);
    if (alt == null) {
      toast(context, 'Brak innego ćwiczenia z tej grupy przy Twoim sprzęcie.');
      return;
    }
    final out = <PlanItem>[];
    for (var i = 0; i < plan.items.length; i++) {
      final it = plan.items[i];
      if (it.exId != exId) {
        out.add(it);
        continue;
      }
      if (cur.uni) {
        if (it.side == 2) continue; // druga strona doliczona przy pierwszej
        final second = i + 1 < plan.items.length && plan.items[i + 1].exId == exId ? plan.items[i + 1] : null;
        final work = it.work + (second?.work ?? it.work);
        final rest = second?.rest ?? it.rest;
        _addAs(out, alt, it, work, rest);
      } else {
        _addAs(out, alt, it, it.work, it.rest);
      }
    }
    setState(() => plan.items = out);
  }

  void _addAs(List<PlanItem> out, Exercise e, PlanItem like, int work, int rest) {
    if (e.uni) {
      final half = (work / 2).round().clamp(15, 60);
      final w = like.reps != null ? work : half;
      out.add(PlanItem(exId: e.id, work: w, rest: 5, phase: like.phase, side: 1, round: like.round, rounds: like.rounds, reps: like.reps, tag: like.tag));
      out.add(PlanItem(exId: e.id, work: w, rest: rest, phase: like.phase, side: 2, round: like.round, rounds: like.rounds, reps: like.reps, tag: like.tag));
    } else {
      out.add(PlanItem(exId: e.id, work: work, rest: rest, phase: like.phase, round: like.round, rounds: like.rounds, reps: like.reps, tag: like.tag));
    }
  }

  @override
  Widget build(BuildContext context) {
    final lib = Library.instance;
    final sections = <Widget>[];
    for (final ph in Phase.values) {
      final items = plan.items.where((i) => i.phase == ph).toList();
      if (items.isEmpty) continue;
      final rounds = items.fold(1, (m, i) => i.rounds > m ? i.rounds : m);
      final secs = items.fold(0, (a, i) => a + i.work + i.rest);
      sections.add(SectionTitle(
        ph != Phase.main
            ? phaseLabel[ph]!
            : switch (plan.format) {
                WorkoutFormat.tabata => '${phaseLabel[ph]} · tabata',
                WorkoutFormat.sets || WorkoutFormat.supersets => '${phaseLabel[ph]} · ${formatLabel[plan.format]!.toLowerCase()}',
                _ => rounds > 1 ? '${phaseLabel[ph]} · $rounds × obwód' : phaseLabel[ph]!,
              },
        trailing: Text(fmtMin(secs), style: const TextStyle(color: C.muted)),
      ));
      final shown = <String>{};
      final rows = <Widget>[];
      for (final it in items) {
        if (!shown.add(it.exId)) continue;
        final e = lib[it.exId];
        if (e == null) continue;
        // ile serii / interwałów tego ćwiczenia w fazie (strony liczymy raz)
        final mine = items.where((x) => x.exId == it.exId && x.side != 2).toList();
        final n = mine.length;
        final String dose;
        if (it.reps != null) {
          dose = '${n > 1 ? '$n × ' : ''}${it.reps} powt.${e.uni ? ' na stronę' : ''}';
        } else {
          final w = '${it.work} s';
          dose = '${n > 1 ? '$n × ' : ''}$w${e.uni && it.side == 0 ? '' : (e.uni ? ' na stronę' : '')}';
        }
        final approx = it.reps == null ? e.repsFor(it.work) : null;
        final rest = mine.length > 1 ? mine.first.rest : it.rest;
        rows.add(ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          leading: FigureThumb(e, size: 52),
          title: Text(e.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
            [
              if (it.tag != null && plan.format == WorkoutFormat.supersets) it.tag!.split(' ').first,
              dose,
              if (approx != null && !e.uni && rounds == 1 && n == 1) '~$approx powt.',
              if (rest > 5 && ph == Phase.main && plan.format != WorkoutFormat.tabata) 'przerwa $rest s',
            ].join(' · '),
            style: const TextStyle(color: C.muted),
          ),
          trailing: IconButton(icon: const Icon(Icons.swap_horiz), tooltip: 'Zamień', onPressed: () => _swap(it.exId)),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ExerciseScreen(exercise: e))),
        ));
      }
      sections.add(Card(child: Column(children: rows)));
    }

    return Scaffold(
      appBar: AppBar(title: Text(plan.title), actions: const [Padding(padding: EdgeInsets.only(right: 12), child: HrBadge())]),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
        children: [
          Row(children: [
            Stat('minut', '${plan.minutes}'),
            const SizedBox(width: 24),
            Expanded(child: Stat(formatLabel[plan.format]!.toLowerCase(), plan.intensity, color: C.accent)),
          ]),
          ...sections,
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start'),
            onPressed: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => PlayerScreen(plan: plan)),
            ),
          ),
        ),
      ),
    );
  }
}
