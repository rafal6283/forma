import 'package:flutter/material.dart';

import '../core/coach.dart';
import '../core/report.dart';
import '../core/store.dart';
import 'fit_test_screen.dart';
import 'insights.dart';
import 'theme.dart';
import 'widgets.dart';

/// Raport tygodnia od trenera: liczby, co poszło dobrze, co poprawić, prognoza i miesiąc.
class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  late int weeksAgo = WeekReport.defaultWeeksAgo(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final s = Store.instance;
    final r = WeekReport.of(coach(), tests: s.tests, program: s.program, weeksAgo: weeksAgo);
    final range = '${r.monday.day}.${r.monday.month.toString().padLeft(2, '0')} – '
        '${r.sunday.day}.${r.sunday.month.toString().padLeft(2, '0')}';
    return Scaffold(
      appBar: AppBar(title: const Text('Raport tygodnia')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
        Row(children: [
          IconButton(
            tooltip: 'Wcześniejszy tydzień',
            onPressed: weeksAgo < 12 ? () => setState(() => weeksAgo++) : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Column(children: [
              Text(range, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              Text(r.current ? 'tydzień w trakcie' : (weeksAgo == 1 ? 'poprzedni tydzień' : '$weeksAgo tyg. temu'),
                  style: TextStyle(color: C.muted, fontSize: 12)),
            ]),
          ),
          IconButton(
            tooltip: 'Późniejszy tydzień',
            onPressed: weeksAgo > 0 ? () => setState(() => weeksAgo--) : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ]),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Row(children: [
                Expanded(
                    child: Stat('treningi (cel ${r.target})', '${r.sessions}/${r.target}',
                        color: r.sessions >= r.target ? C.good : null)),
                Expanded(child: Stat('minuty', '${r.minutes}', color: null)),
                Expanded(child: Stat('kcal', '${r.kcal}')),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: Stat('serie', '${r.sets}')),
                Expanded(child: Stat('powtórzenia', '${r.reps}')),
                Expanded(child: Stat('śr. wysiłek', r.sessions == 0 ? '–' : r.avgRpe.toStringAsFixed(1))),
              ]),
              if (r.prevSessions > 0 || r.prevMinutes > 0) ...[
                const SizedBox(height: 10),
                Text(_trend(r), style: TextStyle(color: C.muted, fontSize: 12)),
              ],
            ]),
          ),
        ),
        _Section(icon: Icons.thumb_up_alt_outlined, color: C.good, title: 'Co poszło dobrze', lines: r.good,
            empty: 'Jeszcze nie ma czym się chwalić — pierwszy trening to zmieni.'),
        _Section(icon: Icons.build_outlined, color: C.warn, title: 'Do poprawy', lines: r.improve,
            empty: 'Nic do poprawy — tak trzymaj!'),
        _Section(icon: Icons.trending_up, color: C.calm, title: 'Prognoza na kolejny tydzień', lines: r.forecast, empty: ''),
        if (r.records.isNotEmpty) ...[
          const SectionTitle('Rekordy tygodnia'),
          Card(
            child: Column(children: [
              for (final rec in r.records.take(6))
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.emoji_events_outlined, color: C.warn),
                  title: Text(rec.name),
                  trailing: Text(rec.label, style: TextStyle(color: C.muted)),
                ),
            ]),
          ),
        ],
        const SectionTitle('Partie w tym tygodniu'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              for (final e in r.groupSets.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    SizedBox(width: 82, child: Text(e.key)),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (e.value / r.setTarget).clamp(0, 1).toDouble(),
                          minHeight: 8,
                          backgroundColor: C.surface2,
                          color: e.value >= r.setTarget ? C.good : (e.value >= r.setTarget ~/ 2 ? C.accent : C.warn),
                        ),
                      ),
                    ),
                    SizedBox(width: 56, child: Text('${e.value}/${r.setTarget}', textAlign: TextAlign.right)),
                  ]),
                ),
            ]),
          ),
        ),
        const BalanceCard(),
        const SectionTitle('Miesiąc'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Stat('treningi (4 tyg.)', '${r.month}')),
                Expanded(child: Stat('wcześniej', '${r.prevMonth}')),
                Expanded(
                  child: Stat(
                    'minuty',
                    r.prevMonthMin == 0 ? '${r.monthMin}' : '${r.monthChangePct >= 0 ? '+' : ''}${r.monthChangePct}%',
                    color: r.monthChangePct > 0 ? C.good : (r.monthChangePct < 0 ? C.warn : null),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              if (r.fitNow == null)
                Text('Brak testu formy — zrób pierwszy, żeby co miesiąc widzieć postęp.', style: TextStyle(color: C.muted))
              else ...[
                Text(
                  r.fitBefore == null
                      ? 'Test formy: ${r.fitNow!.score}/100 (${fmtDate(r.fitNow!.at)}). Kolejny pokaże zmianę.'
                      : 'Test formy: ${r.fitNow!.score}/100 — wcześniej ${r.fitBefore!.score}/100 '
                          '(${fmtDate(r.fitBefore!.at)}).',
                ),
                for (final d in r.fitDelta.entries)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(children: [
                      Icon(d.value >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                          size: 16, color: d.value >= 0 ? C.good : C.bad),
                      const SizedBox(width: 6),
                      Expanded(child: Text(d.key)),
                      Text('${d.value >= 0 ? '+' : ''}${d.value} pkt', style: TextStyle(color: C.muted)),
                    ]),
                  ),
              ],
              if (r.testDue) ...[
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FitTestScreen())),
                  icon: const Icon(Icons.speed),
                  label: const Text('Zrób test formy'),
                ),
              ],
            ]),
          ),
        ),
      ]),
    );
  }

  String _trend(WeekReport r) {
    final d = r.minutes - r.prevMinutes;
    final sign = d > 0 ? '+' : '';
    return 'Tydzień wcześniej: ${r.prevSessions} treningi, ${r.prevMinutes} min ($sign$d min).';
  }
}

class _Section extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title, empty;
  final List<String> lines;
  const _Section({required this.icon, required this.color, required this.title, required this.lines, required this.empty});

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty && empty.isEmpty) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 8),
            if (lines.isEmpty) Text(empty, style: TextStyle(color: C.muted)),
            for (final l in lines)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 7, right: 8),
                    child: Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  ),
                  Expanded(child: Text(l, style: const TextStyle(height: 1.35))),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Karta na ekranie głównym: skrót raportu i przejście do pełnego.
class ReportCard extends StatelessWidget {
  const ReportCard({super.key});

  @override
  Widget build(BuildContext context) {
    final s = Store.instance;
    final r = WeekReport.of(coach(), tests: s.tests, program: s.program, weeksAgo: WeekReport.defaultWeeksAgo(DateTime.now()));
    final headline = r.good.isNotEmpty ? r.good.first : (r.improve.isNotEmpty ? r.improve.first : r.forecast.first);
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: const CircleAvatar(backgroundColor: Color(0x33FF6A3D), child: Icon(Icons.assignment_outlined, color: C.accent)),
        title: Text(r.current ? 'Raport tygodnia' : 'Podsumowanie poprzedniego tygodnia',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(headline, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: C.muted)),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportScreen())),
      ),
    );
  }
}

/// Dla testów i innych ekranów: tekstowa wersja raportu (np. do udostępnienia).
String reportText(WeekReport r) => [
      'Forma — raport ${fmtDate(r.monday)} – ${fmtDate(r.sunday)}',
      'Treningi: ${r.sessions}/${r.target}, ${r.minutes} min, ${r.kcal} kcal',
      if (r.good.isNotEmpty) 'Dobrze: ${r.good.join(' ')}',
      if (r.improve.isNotEmpty) 'Do poprawy: ${r.improve.join(' ')}',
      'Prognoza: ${r.forecast.join(' ')}',
    ].join('\n');
