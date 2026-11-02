import 'package:flutter/material.dart';

import '../core/catalog.dart';
import '../core/coach.dart';
import '../core/library.dart';
import '../core/models.dart';
import '../core/store.dart';
import 'figure_view.dart';
import 'preview_screen.dart';
import 'program_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Gotowe programy i wyzwania.
class CatalogScreen extends StatelessWidget {
  final int tab;
  const CatalogScreen({super.key, this.tab = 0});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        initialIndex: tab,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Programy i wyzwania'),
            bottom: const TabBar(tabs: [Tab(text: 'Programy'), Tab(text: 'Wyzwania')]),
          ),
          body: ListenableBuilder(
            listenable: Store.instance,
            builder: (context, _) => const TabBarView(children: [_Programs(), _Challenges()]),
          ),
        ),
      );
}

class _Programs extends StatelessWidget {
  const _Programs();

  @override
  Widget build(BuildContext context) {
    final s = Store.instance;
    final active = s.program?.active == true ? s.program : null;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
      if (active != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text('Teraz: ${active.name} — ${active.doneCount}/${active.days.length} treningów',
              style: const TextStyle(color: C.accent, fontWeight: FontWeight.w600)),
        ),
      for (final t in programTemplates) _ProgramTile(t: t, current: active?.templateId == t.id),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProgramScreen())),
        icon: const Icon(Icons.tune),
        label: const Text('Własny plan według celu'),
      ),
    ]);
  }
}

class _ProgramTile extends StatelessWidget {
  final ProgramTemplate t;
  final bool current;
  const _ProgramTile({required this.t, required this.current});

  @override
  Widget build(BuildContext context) {
    final p = Store.instance.profile;
    final missing = t.needs.where((n) => !p.equipment.contains(n)).toList();
    final kinds = t.week.map((w) => kindLabel[w.$1]!).toSet().join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: missing.isNotEmpty ? null : () => _start(context),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(t.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
                if (current) const Icon(Icons.check_circle, color: C.good),
              ]),
              const SizedBox(height: 4),
              Text(t.desc, style: TextStyle(color: C.muted, height: 1.35)),
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [
                Chip(visualDensity: VisualDensity.compact, label: Text('${t.weeks} tyg.')),
                Chip(visualDensity: VisualDensity.compact, label: Text('${t.week.length}× w tygodniu')),
                Chip(visualDensity: VisualDensity.compact, label: Text('${t.minutes} min')),
                if (t.quiet) const Chip(visualDensity: VisualDensity.compact, label: Text('bez skoków')),
                Chip(visualDensity: VisualDensity.compact, label: Text(['', 'dla początkujących', 'średni', 'zaawansowany'][t.level.clamp(1, 3)])),
              ]),
              const SizedBox(height: 6),
              Text(kinds, style: TextStyle(color: C.muted, fontSize: 12)),
              if (missing.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Wymaga: ${missing.map((m) => equipmentLabel[m] ?? m).join(', ')} (zaznacz w Ustawieniach)',
                      style: const TextStyle(color: C.warn)),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _start(BuildContext context) async {
    final s = Store.instance;
    final days = await showModalBottomSheet<List<int>>(
      context: context,
      showDragHandle: true,
      builder: (_) => _DaysSheet(count: t.week.length),
    );
    if (days == null || !context.mounted) return;
    if (s.program?.active == true &&
        !await confirm(context, 'Zmienić plan?', 'Obecny plan „${s.program!.name}” zostanie zakończony. Historia zostaje.',
            ok: 'Zmień')) {
      return;
    }
    final pr = coach().buildProgram(
      weeks: t.weeks,
      weekdays: days,
      minutes: t.minutes,
      week: t.week,
      name: t.name,
      templateId: t.id,
      prefer: t.prefer,
      quiet: t.quiet,
    );
    await s.setProgram(pr);
    if (context.mounted) {
      toast(context, 'Plan „${t.name}” rozpoczęty — pierwszy trening czeka na ekranie Dziś');
      Navigator.pop(context);
    }
  }
}

class _DaysSheet extends StatefulWidget {
  final int count;
  const _DaysSheet({required this.count});

  @override
  State<_DaysSheet> createState() => _DaysSheetState();
}

class _DaysSheetState extends State<_DaysSheet> {
  late final days = defaultWeekdays(widget.count).toSet();
  static const names = ['pon', 'wt', 'śr', 'czw', 'pt', 'sob', 'ndz'];

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Wybierz ${widget.count} dni treningowe', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (var d = 1; d <= 7; d++)
                FilterChip(
                  label: Text(names[d - 1]),
                  selected: days.contains(d),
                  onSelected: (v) => setState(() => v ? days.add(d) : days.remove(d)),
                ),
            ]),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: days.length == widget.count ? () => Navigator.pop(context, days.toList()..sort()) : null,
              child: Text(days.length == widget.count ? 'Zaczynamy' : 'Zaznacz ${widget.count} dni (teraz ${days.length})'),
            ),
          ]),
        ),
      );
}

class _Challenges extends StatelessWidget {
  const _Challenges();

  @override
  Widget build(BuildContext context) {
    final s = Store.instance;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
      Text(
        'Jedno ćwiczenie codziennie, z rosnącym celem. Pominięty dzień niczego nie psuje — wracasz tam, gdzie skończyłeś.',
        style: TextStyle(color: C.muted, height: 1.35),
      ),
      const SizedBox(height: 12),
      for (final c in challengeDefs) ChallengeTile(c: c, progress: s.challenges[c.id]),
    ]);
  }
}

/// Karta wyzwania (w katalogu i na ekranie „Dziś”).
class ChallengeTile extends StatelessWidget {
  final ChallengeDef c;
  final ChallengeProgress? progress;
  final bool compact;
  const ChallengeTile({super.key, required this.c, this.progress, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final lib = Library.instance;
    final s = Store.instance;
    final e = lib[c.exId];
    final p = progress;
    final active = p != null && p.active;
    final day = p?.nextDay ?? 1;
    final finished = p != null && p.done.length >= c.days;
    final doneToday = p != null &&
        p.done.values.any((id) => s.sessions.any((x) => x.id == id && DateUtils.isSameDay(x.start, DateTime.now())));
    final easier = s.profile.level < 2.2 && c.easierEx != null;
    final missing = e != null && !e.availableWith(s.profile.equipment);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            if (e != null) FigureThumb(e, size: 64),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                if (!compact) Text(c.desc, style: TextStyle(color: C.muted, fontSize: 13)),
                const SizedBox(height: 6),
                if (active || finished) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (p!.done.length / c.days).clamp(0, 1).toDouble(),
                      minHeight: 6,
                      backgroundColor: C.surface2,
                      color: finished ? C.good : C.accent,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    finished
                        ? 'Ukończone! 🏆'
                        : doneToday
                            ? 'Dziś zaliczone ✓ · jutro dzień $day: ${c.target(day)}${c.seconds ? ' s' : ' powt.'}'
                            : 'Dzień $day z ${c.days}: ${c.target(day)}${c.seconds ? ' s' : ' powt.'}',
                    style: TextStyle(color: finished || doneToday ? C.good : C.text, fontSize: 13),
                  ),
                ],
                if (missing) Text('Wymaga: ${e!.eq.join(', ')}', style: const TextStyle(color: C.warn, fontSize: 12)),
              ]),
            ),
            const SizedBox(width: 8),
            if (!finished && !missing)
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44), padding: const EdgeInsets.symmetric(horizontal: 14)),
                onPressed: () async {
                  if (!active) {
                    s.challenges[c.id] = ChallengeProgress(c.id, DateTime.now());
                    await s.save();
                  }
                  if (!context.mounted) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => PreviewScreen(plan: challengePlan(c, day, easier: easier))),
                  );
                },
                child: Text(active ? 'Dzień $day' : 'Dołącz'),
              ),
          ]),
        ),
      ),
    );
  }
}
