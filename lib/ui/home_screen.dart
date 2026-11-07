import 'package:flutter/material.dart';

import '../core/activity_import.dart';
import '../core/coach.dart';
import '../core/hr.dart';
import '../core/models.dart';
import '../core/store.dart';
import '../core/strava.dart';
import '../core/trainer.dart';
import 'calendar_screen.dart';
import 'checkin_sheet.dart';
import 'custom_screen.dart';
import 'family_screen.dart';
import 'fatigue_screen.dart';
import 'hrv_screen.dart';
import 'ppg_screen.dart';
import 'preview_screen.dart';
import 'program_screen.dart';
import 'catalog_screen.dart';
import 'fit_test_screen.dart';
import '../core/catalog.dart';
import 'report_screen.dart';
import 'theme.dart';
import 'users.dart';
import 'widgets.dart';

/// „Dziś”: gotowość, trening dobrany przez trenera, tydzień.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  WorkoutPlan? _plan;
  WorkoutKind? _kind; // wybór użytkownika (null = sugestia trenera / plan)
  WorkoutFormat? _format;
  int? _minutes;
  bool _offPlan = false; // użytkownik wybrał coś innego niż dzień planu
  int _seed = 0;
  String? _reason;

  @override
  void initState() {
    super.initState();
    Store.instance.addListener(_onStore);
    _regen();
    refreshHealth();
    Strava.instance.retryPending();
    ActivityImport.instance.run().catchError((_) => (0, null));
  }

  @override
  void dispose() {
    Store.instance.removeListener(_onStore);
    super.dispose();
  }

  int _lastSessions = -1;
  String _lastSig = '';

  void _onStore() {
    // nowy trening, samopoczucie lub dane zdrowia → przelicz propozycję
    final s = Store.instance;
    final sig = '${s.sessions.length}|${s.todayCheckIn?.at}|${s.todayHrv?.at}|${s.health.sleepHours}|'
        '${s.health.restingHr}|${s.profile.level}|${s.profile.minutes}|${s.profile.equipment}|${s.profile.limits}|'
        '${s.profile.goal}|${s.profile.noJumping}|${s.profile.warmup}|${s.profile.cooldown}|${s.profile.activeLimits}|${s.program?.id}|${s.program?.doneCount}|${s.program?.active}';
    if (sig != _lastSig) {
      if (s.sessions.length != _lastSessions && _lastSessions >= 0) {
        _kind = null;
        _format = null;
        _offPlan = false;
      }
      _lastSessions = s.sessions.length;
      _lastSig = sig;
      _regen();
    } else if (mounted) {
      setState(() {});
    }
  }

  void _regen() {
    final t = coach();
    final r = t.readiness();
    final pr = Store.instance.program;
    final day = pr != null && pr.active && !_offPlan && _kind == null ? pr.next : null;
    if (day != null) {
      // dzień z planu — przy słabej gotowości lżej, ale nadal według planu
      final light = r.score < 40;
      final perWeek = pr!.weekdays.length;
      final late = DateTime.now().difference(day.date).inDays;
      _reason = 'Plan „${pr.name}”: tydzień ${day.week}/${pr.weeks}, trening ${day.index}/$perWeek'
          '${late > 1 ? ' (zaległy od ${fmtDate(day.date)})' : ''}${day.deload ? ' — tydzień lżejszy' : ''}'
          '${light ? '. Gotowość niska, więc dziś mniejsza objętość.' : '.'}';
      _plan = t.generate(
        kind: day.kind,
        format: day.format,
        readiness: r,
        minutes: _minutes ?? day.minutes,
        seed: _seed,
        reason: _reason,
        load: light ? day.load * 0.7 : day.load,
        programDay: day.id,
        prefer: pr.prefer.toSet(),
        quiet: pr.quiet,
      );
    } else {
      var kind = _kind;
      String? reason;
      if (kind == null) {
        final rec = t.recommendKind(r);
        kind = rec.$1;
        reason = rec.$2;
      }
      _reason = reason;
      _plan = t.generate(kind: kind, format: _format, readiness: r, minutes: _minutes, seed: _seed, reason: reason);
    }
    if (mounted) setState(() {});
  }

  Future<void> _chooseKind() async {
    final res = await showModalBottomSheet<(WorkoutKind?, WorkoutFormat?, int?)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => _KindSheet(kind: _kind, format: _format, minutes: _minutes ?? Store.instance.profile.minutes),
    );
    if (res == null) return;
    _kind = res.$1;
    _format = res.$2;
    _minutes = res.$3;
    _offPlan = _kind != null;
    _seed++;
    _regen();
  }

  @override
  Widget build(BuildContext context) {
    final s = Store.instance;
    final t = coach();
    final r = t.readiness();
    final plan = _plan;
    final now = DateTime.now();
    final hello = now.hour < 11 ? 'Dzień dobry' : now.hour < 18 ? 'Cześć' : 'Dobry wieczór';
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: refreshHealth,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(fmtDate(now), style: TextStyle(color: C.muted)),
                    Text(s.profile.name.isEmpty ? hello : '$hello, ${s.profile.name}',
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                  ]),
                ),
                const HrBadge(),
                const SizedBox(width: 8),
                const UserChip(),
              ]),
              const SizedBox(height: 12),
              const StreakStrip(),
              const SizedBox(height: 4),
              _ReadinessCard(r: r),
              const SectionTitle('Trener proponuje'),
              if (plan != null) _PlanCard(plan: plan, onChange: _chooseKind, onShuffle: () {
                _seed++;
                _regen();
              }, reason: _reason),
              const SectionTitle('Plan'),
              const ProgramCard(),
              const SizedBox(height: 10),
              const _Extras(),
              const SectionTitle('Ten tydzień'),
              _WeekCard(sessions: s.sessions, target: s.profile.daysPerWeek),
              const SizedBox(height: 10),
              const ReportCard(),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadinessCard extends StatelessWidget {
  final Readiness r;
  const _ReadinessCard({required this.r});

  @override
  Widget build(BuildContext context) {
    final s = Store.instance;
    final checked = s.todayCheckIn != null;
    final color = C.readiness(r.score);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Ring(
              value: r.score / 100,
              color: color,
              size: 84,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${r.score}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
              ]),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Gotowość', style: TextStyle(color: C.muted)),
                Text(r.tier, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
                const SizedBox(height: 4),
                Text(
                  r.hasData ? 'Na podstawie snu, tętna, samopoczucia i ostatnich treningów.' : 'Brak danych — szacunek.',
                  style: TextStyle(color: C.muted, fontSize: 12),
                ),
              ]),
            ),
          ]),
          if (r.factors.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final f in r.factors)
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text('${f.label}: ${f.value}'),
                  avatar: Icon(
                    f.effect > 0 ? Icons.arrow_upward : (f.effect < 0 ? Icons.arrow_downward : Icons.remove),
                    size: 16,
                    color: f.effect > 0 ? C.good : (f.effect < 0 ? C.bad : C.muted),
                  ),
                ),
            ]),
          ],
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => showCheckIn(context),
                icon: Icon(checked ? Icons.check_circle : Icons.mood, size: 18),
                label: Text(checked ? 'Samopoczucie ✓' : 'Jak się czujesz?'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ListenableBuilder(
                listenable: HrService.instance,
                builder: (context, _) => OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => HrService.instance.connected ? const HrvScreen() : const PpgScreen(),
                    ),
                  ),
                  icon: Icon(s.todayHrv != null ? Icons.check_circle : Icons.monitor_heart_outlined, size: 18),
                  label: Text(s.todayHrv != null ? 'HRV ${s.todayHrv!.rmssd.round()} ms' : 'Pomiar HRV'),
                ),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final WorkoutPlan plan;
  final VoidCallback onChange, onShuffle;
  final String? reason;
  const _PlanCard({required this.plan, required this.onChange, required this.onShuffle, this.reason});

  @override
  Widget build(BuildContext context) {
    final ids = <String>{for (final i in plan.items.where((i) => i.phase == Phase.main)) i.exId};
    final rounds = plan.items.where((i) => i.phase == Phase.main).fold(1, (m, i) => i.rounds > m ? i.rounds : m);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PreviewScreen(plan: plan))),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(plan.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              ),
              IconButton(onPressed: onShuffle, icon: const Icon(Icons.shuffle), tooltip: 'Inne ćwiczenia'),
              IconButton(onPressed: onChange, icon: const Icon(Icons.tune), tooltip: 'Zmień rodzaj i czas'),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              Stat('minut', '${plan.minutes}'),
              const SizedBox(width: 24),
              Stat('ćwiczeń', '${ids.length}'),
              const SizedBox(width: 24),
              if (rounds > 1) Stat('rundy', '$rounds'),
            ]),
            const SizedBox(height: 10),
            Text(plan.intensity, style: const TextStyle(color: C.accent, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            for (final line in plan.reasons)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(
                    padding: EdgeInsets.only(top: 3, right: 8),
                    child: Icon(Icons.auto_awesome, size: 14, color: C.muted),
                  ),
                  Expanded(child: Text(line, style: TextStyle(color: C.muted, height: 1.35))),
                ]),
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PreviewScreen(plan: plan))),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Zobacz i zacznij'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _KindSheet extends StatefulWidget {
  final WorkoutKind? kind;
  final WorkoutFormat? format;
  final int minutes;
  const _KindSheet({required this.kind, required this.format, required this.minutes});

  @override
  State<_KindSheet> createState() => _KindSheetState();
}

class _KindSheetState extends State<_KindSheet> {
  late WorkoutKind? kind = widget.kind;
  late WorkoutFormat? format = widget.format;
  late int minutes = widget.minutes;

  @override
  Widget build(BuildContext context) {
    final hasPlan = Store.instance.program?.active == true;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Partia / rodzaj', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ChoiceChip(
              label: Text(hasPlan ? 'Według planu' : 'Wybór trenera'),
              selected: kind == null,
              onSelected: (_) => setState(() {
                kind = null;
                format = null;
              }),
            ),
            for (final k in WorkoutKind.values)
              ChoiceChip(label: Text(kindLabel[k]!), selected: kind == k, onSelected: (_) => setState(() => kind = k)),
          ]),
          const SizedBox(height: 16),
          const Text('Format', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ChoiceChip(label: const Text('Dobierz sam'), selected: format == null, onSelected: (_) => setState(() => format = null)),
            for (final f in WorkoutFormat.values)
              ChoiceChip(
                label: Text(formatLabel[f]!),
                selected: format == f,
                onSelected: (_) => setState(() {
                  format = f;
                  kind ??= f == WorkoutFormat.flow ? WorkoutKind.mobility : WorkoutKind.fullBody;
                }),
              ),
          ]),
          if (format != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(formatHint[format]!, style: TextStyle(color: C.muted, fontSize: 12)),
            ),
          const SizedBox(height: 16),
          const Text('Czas', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final m in [10, 15, 20, 25, 30, 40, 50, 60])
              ChoiceChip(label: Text('$m min'), selected: minutes == m, onSelected: (_) => setState(() => minutes = m)),
          ]),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Rozgrzewka'),
            subtitle: Text('Dobrana do partii, które dziś pracują', style: TextStyle(color: C.muted, fontSize: 12)),
            value: Store.instance.profile.warmup,
            onChanged: (v) => setState(() {
              Store.instance.profile.warmup = v;
              Store.instance.save();
            }),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Rozciąganie na koniec'),
            subtitle: Text('Wyciszenie mięśni, które pracowały', style: TextStyle(color: C.muted, fontSize: 12)),
            value: Store.instance.profile.cooldown,
            onChanged: (v) => setState(() {
              Store.instance.profile.cooldown = v;
              Store.instance.save();
            }),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () => Navigator.pop(context, (kind, format, minutes)),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: const Text('Ułóż trening'),
          ),
        ]),
      ),
    );
  }
}

class _WeekCard extends StatelessWidget {
  final List<Session> sessions;
  final int target;
  const _WeekCard({required this.sessions, required this.target});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    final week = sessions.where((s) => !s.start.isBefore(monday)).toList();
    final mins = week.fold(0, (a, s) => a + s.duration.inSeconds);
    final kcal = week.fold(0.0, (a, s) => a + s.kcal);
    final days = List.generate(7, (i) {
      final d = monday.add(Duration(days: i));
      return week.where((s) => s.start.year == d.year && s.start.month == d.month && s.start.day == d.day).fold(
            0,
            (a, s) => a + s.duration.inMinutes,
          );
    });
    final done = days.where((m) => m > 0).length;
    const labels = ['P', 'W', 'Ś', 'C', 'P', 'S', 'N'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Row(children: [
            Expanded(child: Stat('dni treningowe (cel $target)', '$done/$target', color: done >= target ? C.good : null)),
            Expanded(child: Stat('czas', fmtMin(mins))),
            Expanded(child: Stat('kcal', '${kcal.round()}')),
          ]),
          const SizedBox(height: 14),
          Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: SizedBox(
                    height: 70,
                    child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                    Container(
                      height: 8 + (days[i].clamp(0, 60) / 60 * 40),
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: days[i] > 0 ? C.accent : C.surface2,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(labels[i],
                        style: TextStyle(
                          color: i == now.weekday - 1 ? C.text : C.muted,
                          fontWeight: i == now.weekday - 1 ? FontWeight.w800 : FontWeight.w400,
                          fontSize: 12,
                        )),
                    ]),
                  ),
                ),
            ],
          ),
        ]),
      ),
    );
  }
}

/// Wyzwania w toku, katalog programów i przypomnienie o teście formy.
class _Extras extends StatelessWidget {
  const _Extras();

  @override
  Widget build(BuildContext context) {
    final s = Store.instance;
    final active = [
      for (final c in challengeDefs)
        if (s.challenges[c.id]?.active == true && (s.challenges[c.id]!.done.length < c.days)) c,
    ];
    final lastTest = s.tests.isEmpty ? null : s.tests.last;
    final testDue = lastTest == null ? s.sessions.length >= 1 : DateTime.now().difference(lastTest.at).inDays >= 28;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final c in active) ChallengeTile(c: c, progress: s.challenges[c.id], compact: true),
      FilledButton.tonalIcon(
        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PreviewScreen(plan: coach().quick7()))),
        icon: const Icon(Icons.bolt),
        label: const Text('Szybkie 7 minut — start bez wyborów'),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomListScreen())),
            icon: const Icon(Icons.playlist_add, size: 18),
            label: const Text('Moje treningi'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FamilyScreen())),
            icon: const Icon(Icons.groups_outlined, size: 18),
            label: const Text('Rodzina'),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CatalogScreen())),
            icon: const Icon(Icons.auto_awesome_motion, size: 18),
            label: const Text('Programy'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CatalogScreen(tab: 1))),
            icon: const Icon(Icons.emoji_events_outlined, size: 18),
            label: const Text('Wyzwania'),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      const FatigueCard(),
      Card(
        child: ListTile(
          leading: Icon(Icons.speed, color: testDue ? C.accent : C.muted),
          title: Text(lastTest == null ? 'Test formy' : 'Test formy · wynik ${lastTest.score}'),
          subtitle: Text(
            lastTest == null
                ? '10 minut: pompki, przysiady, deska i tętno — punkt wyjścia do porównań'
                : testDue
                    ? 'Minęły 4 tygodnie — czas sprawdzić postęp'
                    : 'Następny za ${28 - DateTime.now().difference(lastTest.at).inDays} dni',
            style: TextStyle(color: C.muted),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FitTestScreen())),
        ),
      ),
    ]);
  }
}
