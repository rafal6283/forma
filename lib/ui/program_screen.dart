import 'package:flutter/material.dart';

import '../core/coach.dart';
import '../core/models.dart';
import '../core/store.dart';
import '../core/trainer.dart';
import 'theme.dart';
import 'widgets.dart';

const _dayNames = ['pon', 'wt', 'śr', 'czw', 'pt', 'sob', 'ndz'];

List<int> defaultWeekdays(int n) => switch (n) {
      1 => [3],
      2 => [2, 5],
      3 => [1, 3, 5],
      4 => [1, 2, 4, 5],
      5 => [1, 2, 3, 5, 6],
      6 => [1, 2, 3, 4, 5, 6],
      _ => [1, 2, 3, 4, 5, 6, 7],
    };

/// Karta planu na ekranie „Dziś”.
class ProgramCard extends StatelessWidget {
  const ProgramCard({super.key});

  @override
  Widget build(BuildContext context) {
    final pr = Store.instance.program;
    void open() => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProgramScreen()));
    if (pr == null || !pr.active) {
      return Card(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: const Icon(Icons.event_note, color: C.accent),
          title: Text(pr == null ? 'Plan na kilka tygodni' : 'Plan „${pr.name}” zakończony'),
          subtitle: const Text('Trener rozpisze treningi na tygodnie, z progresją i tygodniami lżejszymi.',
              style: TextStyle(color: C.muted)),
          trailing: const Icon(Icons.chevron_right),
          onTap: open,
        ),
      );
    }
    final n = pr.next;
    final week = pr.currentWeek(DateTime.now());
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: open,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(pr.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
              Text('tydzień $week/${pr.weeks}', style: const TextStyle(color: C.muted)),
            ]),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: pr.progress, minHeight: 6, backgroundColor: C.surface2, color: C.accent),
            ),
            const SizedBox(height: 8),
            Text('${pr.doneCount} z ${pr.days.length} treningów'
                '${n != null ? ' · następny: ${kindLabel[n.kind]}, ${formatLabel[n.format]!.toLowerCase()} (${fmtDate(n.date)})' : ''}',
                style: const TextStyle(color: C.muted)),
          ]),
        ),
      ),
    );
  }
}

/// Plan wielotygodniowy: kreator i podgląd tygodni.
class ProgramScreen extends StatefulWidget {
  const ProgramScreen({super.key});

  @override
  State<ProgramScreen> createState() => _ProgramScreenState();
}

class _ProgramScreenState extends State<ProgramScreen> {
  final s = Store.instance;
  late int weeks = 6;
  late List<int> weekdays = defaultWeekdays(s.profile.daysPerWeek);
  late int minutes = s.profile.minutes;
  bool creating = false;

  @override
  Widget build(BuildContext context) {
    final pr = s.program;
    final showWizard = creating || pr == null || !pr.active;
    return Scaffold(
      appBar: AppBar(title: Text(showWizard ? 'Nowy plan' : 'Plan'), actions: [
        if (!showWizard)
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'new') setState(() => creating = true);
              if (v == 'end' &&
                  await confirm(context, 'Zakończyć plan?', 'Historia treningów zostaje. Trener wróci do doboru dzień po dniu.',
                      ok: 'Zakończ')) {
                pr!.active = false;
                await s.save();
                if (mounted) setState(() {});
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'new', child: Text('Nowy plan')),
              PopupMenuItem(value: 'end', child: Text('Zakończ plan')),
            ],
          ),
      ]),
      body: showWizard ? _wizard() : _overview(pr!),
    );
  }

  Widget _wizard() {
    final t = coach();
    final tpl = Trainer.weekTemplate(s.profile.goal, weekdays.length);
    final wd = [...weekdays]..sort();
    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
      Card(
        child: ListTile(
          title: Text('Cel: ${goalLabel[s.profile.goal]}'),
          subtitle: const Text('Zmienisz go w Ustawieniach', style: TextStyle(color: C.muted)),
          leading: const Icon(Icons.flag_outlined, color: C.accent),
        ),
      ),
      const SectionTitle('Długość'),
      Wrap(spacing: 8, children: [
        for (final w in [4, 6, 8, 12])
          ChoiceChip(label: Text('$w tygodni'), selected: weeks == w, onSelected: (_) => setState(() => weeks = w)),
      ]),
      const SectionTitle('Dni treningowe'),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (var d = 1; d <= 7; d++)
          FilterChip(
            label: Text(_dayNames[d - 1]),
            selected: weekdays.contains(d),
            onSelected: (v) => setState(() {
              if (v) {
                weekdays.add(d);
              } else if (weekdays.length > 1) {
                weekdays.remove(d);
              }
            }),
          ),
      ]),
      const SectionTitle('Czas treningu'),
      Slider(
        value: minutes.toDouble(),
        min: 15,
        max: 60,
        divisions: 9,
        label: '$minutes min',
        onChanged: (v) => setState(() => minutes = v.round()),
      ),
      Text('$minutes min (mobilność i rozciąganie krócej)', style: const TextStyle(color: C.muted)),
      const SectionTitle('Typowy tydzień'),
      Card(
        child: Column(children: [
          for (var i = 0; i < wd.length; i++)
            ListTile(
              dense: true,
              leading: Text(_dayNames[wd[i] - 1], style: const TextStyle(fontWeight: FontWeight.w700)),
              title: Text(kindLabel[tpl[i % tpl.length].$1]!),
              subtitle: Text(formatLabel[tpl[i % tpl.length].$2]!, style: const TextStyle(color: C.muted)),
            ),
        ]),
      ),
      const SizedBox(height: 8),
      const Text(
        'Co 4. tydzień jest lżejszy (mniej serii) — w tym czasie mięśnie nadrabiają regenerację. '
        'W pozostałych objętość rośnie z tygodnia na tydzień, a cele powtórzeń idą w górę, gdy robisz wszystkie serie. '
        'Opuszczony trening nie przepada: czeka jako następny.',
        style: TextStyle(color: C.muted, height: 1.4),
      ),
      const SizedBox(height: 16),
      FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        onPressed: () async {
          final p = t.buildProgram(weeks: weeks, weekdays: weekdays, minutes: minutes);
          await s.setProgram(p);
          if (mounted) setState(() => creating = false);
        },
        child: const Text('Rozpocznij plan'),
      ),
    ]);
  }

  Widget _overview(Program pr) {
    final today = DateTime.now();
    final next = pr.next;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
      Text(pr.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
      Text('Od ${fmtDate(pr.start)} · ${pr.doneCount}/${pr.days.length} treningów', style: const TextStyle(color: C.muted)),
      const SizedBox(height: 10),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(value: pr.progress, minHeight: 8, backgroundColor: C.surface2, color: C.accent),
      ),
      for (var w = 1; w <= pr.weeks; w++) ...[
        SectionTitle(
          'Tydzień $w${Trainer.weekLoad(w) < 0.95 ? ' · lżejszy' : ''}',
          trailing: Text('×${Trainer.weekLoad(w).toStringAsFixed(2).replaceAll('.', ',')}',
              style: const TextStyle(color: C.muted, fontSize: 12)),
        ),
        Card(
          child: Column(children: [
            for (final d in pr.days.where((d) => d.week == w))
              ListTile(
                dense: true,
                leading: Icon(
                  d.done
                      ? Icons.check_circle
                      : d.skipped
                          ? Icons.remove_circle_outline
                          : d == next
                              ? Icons.play_circle
                              : Icons.circle_outlined,
                  color: d.done ? C.good : (d == next ? C.accent : C.muted),
                ),
                title: Text('${kindLabel[d.kind]} · ${formatLabel[d.format]}',
                    style: TextStyle(decoration: d.skipped ? TextDecoration.lineThrough : null)),
                subtitle: Text(
                  '${fmtDate(d.date)} · ${d.minutes} min'
                  '${!d.done && !d.skipped && d.date.isBefore(DateTime(today.year, today.month, today.day)) ? ' · zaległy' : ''}',
                  style: const TextStyle(color: C.muted),
                ),
                trailing: d.done || d.skipped
                    ? (d.skipped
                        ? TextButton(
                            onPressed: () async {
                              d.skipped = false;
                              await s.save();
                              setState(() {});
                            },
                            child: const Text('Przywróć'))
                        : null)
                    : PopupMenuButton<String>(
                        onSelected: (v) async {
                          if (v == 'skip') {
                            d.skipped = true;
                            if (pr.next == null) pr.active = false;
                            await s.save();
                            setState(() {});
                          }
                        },
                        itemBuilder: (_) => const [PopupMenuItem(value: 'skip', child: Text('Pomiń ten trening'))],
                      ),
              ),
          ]),
        ),
      ],
    ]);
  }
}
