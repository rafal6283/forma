import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/health_sync.dart';
import '../core/library.dart';
import '../core/models.dart';
import '../core/store.dart';
import '../core/strava.dart';
import '../core/tcx.dart';
import 'muscle_map.dart';
import 'session_widgets.dart';
import 'stats_screen.dart';
import 'report_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Historia treningów i postępy.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Store.instance,
        builder: (context, _) {
          final s = Store.instance;
          final list = s.sessions.reversed.toList();
          final now = DateTime.now();
          final month = s.sessions.where((x) => now.difference(x.start).inDays < 30).toList();
          return DefaultTabController(
            length: 2,
            child: Scaffold(
            appBar: AppBar(
              title: const Text('Postępy'),
              actions: [
                IconButton(
                  tooltip: 'Raport tygodnia',
                  icon: const Icon(Icons.assignment_outlined),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportScreen())),
                ),
              ],
              bottom: const TabBar(tabs: [Tab(text: 'Przegląd'), Tab(text: 'Treningi')]),
            ),
            body: TabBarView(children: [
              const StatsView(),
              list.isEmpty
                ? Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('Tu pojawią się Twoje treningi.', style: TextStyle(color: C.muted)),
                    ),
                  )
                : ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Ostatnie 30 dni', style: TextStyle(color: C.muted)),
                          const SizedBox(height: 10),
                          Row(children: [
                            Expanded(child: Stat('treningi', '${month.length}')),
                            Expanded(child: Stat('czas', fmtMin(month.fold(0, (a, x) => a + x.duration.inSeconds)))),
                            Expanded(child: Stat('kcal', '${month.fold(0.0, (a, x) => a + x.kcal).round()}')),
                            Expanded(child: Stat('poziom', s.profile.level.toStringAsFixed(1).replaceAll('.', ','))),
                          ]),
                          const SizedBox(height: 10),
                          Text('Seria: ${_streakWeeks(s.sessions, s.profile.daysPerWeek)} tyg. z celem ${s.profile.daysPerWeek} treningów',
                              style: TextStyle(color: C.muted, fontSize: 12)),
                        ]),
                      ),
                    ),
                    const SectionTitle('Treningi'),
                    for (final x in list)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Card(
                          child: ListTile(
                            title: Text(x.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              '${fmtDate(x.start)}, ${fmtTime(x.start)} · ${fmtDur(x.duration.inSeconds)} · ${x.kcal.round()} kcal'
                              '${x.avgHr != null ? ' · ♥ ${x.avgHr}' : ''}',
                              style: TextStyle(color: C.muted, fontSize: 12),
                            ),
                            trailing: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Text('RPE ${x.rpe}', style: const TextStyle(fontWeight: FontWeight.w700)),
                              if (x.inHealth) const Icon(Icons.favorite, size: 14, color: C.good),
                            ]),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => SessionScreen(session: x)),
                            ),
                          ),
                        ),
                      ),
                  ]),
            ]),
          ),
          );
        },
      );

  /// Ile tygodni z rzędu (licząc od bieżącego lub poprzedniego) spełniło cel.
  static int _streakWeeks(List<Session> sessions, int target) {
    final now = DateTime.now();
    var monday = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    int count(DateTime from) {
      final to = from.add(const Duration(days: 7));
      return sessions
          .where((s) => !s.start.isBefore(from) && s.start.isBefore(to))
          .map((s) => '${s.start.year}-${s.start.month}-${s.start.day}')
          .toSet()
          .length;
    }

    var streak = 0;
    if (count(monday) >= target) streak++;
    while (true) {
      monday = monday.subtract(const Duration(days: 7));
      if (count(monday) >= target) {
        streak++;
      } else {
        break;
      }
    }
    return streak;
  }
}

class SessionScreen extends StatefulWidget {
  final Session session;
  const SessionScreen({super.key, required this.session});

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  bool sending = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final lib = Library.instance;
    // zsumowany czas na ćwiczenie
    final per = <String, int>{};
    final repsBy = <String, List<int>>{};
    for (final d in s.done) {
      if (d.reps != null && d.side != 2) repsBy.putIfAbsent(d.exId, () => []).add(d.reps!);
    }
    for (final d in s.done) {
      per[d.exId] = (per[d.exId] ?? 0) + d.seconds;
    }
    return Scaffold(
      appBar: AppBar(title: Text(s.title), actions: [
        IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: () async {
            if (await confirm(context, 'Usunąć trening?', 'Nie usunie go z Health Connect.', ok: 'Usuń')) {
              await Store.instance.deleteSession(s);
              if (context.mounted) Navigator.pop(context);
            }
          },
        ),
      ]),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
        Text('${fmtDate(s.start)}, ${fmtTime(s.start)}–${fmtTime(s.end)}', style: TextStyle(color: C.muted)),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SessionStats(s),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: Stat('RPE', '${s.rpe}/10')),
                Expanded(child: Stat('gotowość', s.readiness > 0 ? '${s.readiness}' : '–')),
                Expanded(child: Stat('wykonano', '${(s.completion * 100).round()}%')),
              ]),
              if (s.hr.where((v) => v > 0).length > 2) ...[
                const SizedBox(height: 16),
                HrChart(s),
                const SizedBox(height: 10),
                ZonesBar(s.zones),
              ],
            ]),
          ),
        ),
        if (muscleLoad(s.done).isNotEmpty) ...[
          const SectionTitle('Pracujące mięśnie'),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: MuscleMap(muscleLoad(s.done), height: 220))),
        ],
        const SectionTitle('Ćwiczenia'),
        Card(
          child: Column(children: [
            for (final e in per.entries)
              ListTile(
                dense: true,
                title: Text(lib[e.key]?.name ?? e.key),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (s.feedback[e.key] == 1) const Text('trudne  ', style: TextStyle(color: C.bad)),
                  if (s.feedback[e.key] == -1) const Text('łatwe  ', style: TextStyle(color: C.good)),
                  Text(repsBy[e.key] != null ? '${repsBy[e.key]!.join('/')} powt.' : fmtDur(e.value),
                      style: TextStyle(color: C.muted)),
                ]),
              ),
          ]),
        ),
        const SectionTitle('Strava'),
        _StravaCard(session: s),
        if (Store.instance.profile.healthConnect && !s.inHealth) ...[
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: sending
                ? null
                : () async {
                    setState(() => sending = true);
                    final ok = await HealthSync.instance.writeSession(s);
                    if (ok) {
                      s.inHealth = true;
                      await Store.instance.save();
                    }
                    if (!context.mounted) return;
                    setState(() => sending = false);
                    toast(context, ok ? 'Wysłano do Health Connect' : (HealthSync.instance.lastError ?? 'Błąd zapisu'));
                  },
            icon: const Icon(Icons.favorite_border),
            label: const Text('Wyślij do Health Connect'),
          ),
        ],
      ]),
    );
  }
}

class _StravaCard extends StatefulWidget {
  final Session session;
  const _StravaCard({required this.session});

  @override
  State<_StravaCard> createState() => _StravaCardState();
}

class _StravaCardState extends State<_StravaCard> {
  bool busy = false;
  bool? connected;

  @override
  void initState() {
    super.initState();
    Strava.instance.connected().then((v) {
      if (mounted) setState(() => connected = v);
    });
  }

  Future<void> _run(Future<String> Function() f) async {
    setState(() => busy = true);
    try {
      final msg = await f();
      if (mounted) toast(context, msg);
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _exportTcx() async {
    final s = widget.session;
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/forma-${s.start.toIso8601String().substring(0, 16).replaceAll(':', '-')}.tcx');
    await f.writeAsString(sessionTcx(s));
    await SharePlus.instance.share(ShareParams(files: [XFile(f.path)], subject: '${s.title} — Forma'));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final status = s.stravaId != null
        ? 'W Stravie ✓'
        : s.stravaPending
            ? 'Czeka na aktywność z zegarka'
            : 'Nie wysłano';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(status, style: TextStyle(color: s.stravaId != null ? C.good : C.muted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (connected == true && s.stravaId == null) ...[
              FilledButton.tonal(
                onPressed: busy ? null : () => _run(() => Strava.instance.push(s)),
                child: const Text('Uzupełnij z zegarka'),
              ),
              OutlinedButton(
                onPressed: busy ? null : () => _run(() => Strava.instance.push(s, forceUpload: true)),
                child: const Text('Wyślij jako nową'),
              ),
            ],
            if (connected == true && s.stravaId != null)
              OutlinedButton(
                onPressed: busy ? null : () => _run(() => Strava.instance.push(s)),
                child: const Text('Zaktualizuj opis'),
              ),
            OutlinedButton.icon(
              onPressed: _exportTcx,
              icon: const Icon(Icons.ios_share, size: 18),
              label: const Text('Plik TCX'),
            ),
          ]),
          if (connected == false)
            Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Połącz Stravę w Ustawieniach albo wgraj plik TCX na strava.com/upload.',
                  style: TextStyle(color: C.muted, fontSize: 12)),
            ),
        ]),
      ),
    );
  }
}
