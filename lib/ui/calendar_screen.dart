import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/progress.dart';
import '../core/reminders.dart';
import '../core/store.dart';
import 'theme.dart';
import 'widgets.dart';

const _months = [
  'styczeń', 'luty', 'marzec', 'kwiecień', 'maj', 'czerwiec',
  'lipiec', 'sierpień', 'wrzesień', 'październik', 'listopad', 'grudzień',
];

/// Kalendarz: dni z treningiem, serie, pierścień miesiąca, poziom i przypomnienia.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final store = Store.instance;
  late DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? picked;

  @override
  Widget build(BuildContext context) {
    final st = store.streaks;
    final lv = store.level;
    final (done, goal) = st.month(month);
    return Scaffold(
      appBar: AppBar(title: const Text('Kalendarz i seria')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Ring(
                value: goal == 0 ? 0 : (done / goal).clamp(0, 1).toDouble(),
                color: done >= goal ? C.good : C.accent,
                size: 104,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('$done/$goal', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  Text('dni', style: TextStyle(color: C.muted, fontSize: 11)),
                ]),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Text('🔥', style: TextStyle(fontSize: 22)),
                    const SizedBox(width: 6),
                    Text('${st.dayStreak} ${st.dayStreak == 1 ? 'dzień' : 'dni'} z rzędu',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  ]),
                  const SizedBox(height: 4),
                  Text('Cel tygodnia: ${st.thisWeek}/${st.weekTarget} · tygodnie z rzędu: ${st.weekStreak}',
                      style: TextStyle(color: C.muted)),
                  Text('Najdłuższa seria: ${st.bestDayStreak} dni', style: TextStyle(color: C.muted)),
                  if (st.riskText != null) ...[
                    const SizedBox(height: 6),
                    Text(st.riskText!, style: const TextStyle(color: C.warn, fontWeight: FontWeight.w600)),
                  ],
                ]),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          IconButton(
            onPressed: () => setState(() => month = DateTime(month.year, month.month - 1)),
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Text('${_months[month.month - 1]} ${month.year}',
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
          IconButton(
            onPressed: month.isBefore(DateTime(DateTime.now().year, DateTime.now().month))
                ? () => setState(() => month = DateTime(month.year, month.month + 1))
                : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ]),
        _MonthGrid(month: month, st: st, picked: picked, onPick: (d) => setState(() => picked = d)),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _dot(C.accent),
          Text(' trening w Formie   ', style: TextStyle(color: C.muted, fontSize: 12)),
          _dot(C.calm),
          Text(' bieg, rower, spacer', style: TextStyle(color: C.muted, fontSize: 12)),
        ]),
        if (picked != null) _DayDetails(day: picked!),
        const SectionTitle('Poziom'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: C.accent.withValues(alpha: 0.2),
                  child: Text('${lv.level}', style: const TextStyle(color: C.accent, fontWeight: FontWeight.w800, fontSize: 18)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Poziom ${lv.level} · ${lv.title}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    Text('${lv.xp} pkt · do następnego ${lv.next - lv.xp} pkt', style: TextStyle(color: C.muted)),
                  ]),
                ),
              ]),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: lv.progress, minHeight: 8, backgroundColor: C.surface2, color: C.accent),
              ),
              const SizedBox(height: 12),
              for (final (what, pts) in xpRules)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(children: [
                    Expanded(child: Text(what, style: TextStyle(color: C.muted, fontSize: 13))),
                    Text(pts, style: const TextStyle(fontSize: 13)),
                  ]),
                ),
            ]),
          ),
        ),
        const SectionTitle('Przypomnienia'),
        Card(
          child: Column(children: [
            SwitchListTile(
              title: const Text('Przypominaj o treningu'),
              subtitle: Text('Codziennie, poza dniami z treningiem; wieczorem, gdy seria jest zagrożona',
                  style: TextStyle(color: C.muted)),
              value: store.profile.reminders,
              onChanged: (v) async {
                if (v && !await Reminders.instance.requestPermission()) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Brak zgody na powiadomienia — włącz je w ustawieniach telefonu.')));
                  }
                }
                setState(() => store.profile.reminders = v);
                await store.save();
                await Reminders.instance.reschedule();
              },
            ),
            ListTile(
              enabled: store.profile.reminders,
              leading: const Icon(Icons.schedule),
              title: const Text('Godzina'),
              trailing: Text('${store.profile.reminderHour}:00', style: const TextStyle(fontWeight: FontWeight.w700)),
              onTap: () async {
                final t = await showTimePicker(
                    context: context, initialTime: TimeOfDay(hour: store.profile.reminderHour, minute: 0));
                if (t == null) return;
                setState(() => store.profile.reminderHour = t.hour);
                await store.save();
                await Reminders.instance.reschedule();
              },
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _dot(Color c) => Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle));
}

class _MonthGrid extends StatelessWidget {
  final DateTime month;
  final Streaks st;
  final DateTime? picked;
  final ValueChanged<DateTime> onPick;
  const _MonthGrid({required this.month, required this.st, required this.picked, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month);
    final days = DateTime(month.year, month.month + 1, 0).day;
    final lead = first.weekday - 1;
    final today = DateTime.now();
    final cells = <Widget>[
      for (final d in const ['pn', 'wt', 'śr', 'cz', 'pt', 'sb', 'nd'])
        Center(child: Text(d, style: TextStyle(color: C.muted, fontSize: 12))),
      for (var i = 0; i < lead; i++) const SizedBox(),
      for (var i = 1; i <= days; i++)
        Builder(builder: (context) {
          final d = DateTime(month.year, month.month, i);
          final min = st.minutesByDay[d];
          final forma = st.formaDays.contains(d);
          final isToday = d.year == today.year && d.month == today.month && d.day == today.day;
          final sel = picked == d;
          final color = min == null ? null : (forma ? C.accent : C.calm);
          return InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: min == null ? null : () => onPick(d),
            child: Container(
              margin: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: color?.withValues(alpha: sel ? 0.55 : 0.25),
                shape: BoxShape.circle,
                border: isToday ? Border.all(color: C.text, width: 1.4) : null,
              ),
              alignment: Alignment.center,
              child: Text('$i',
                  style: TextStyle(fontWeight: min != null ? FontWeight.w800 : FontWeight.w400, color: min != null ? C.text : C.muted)),
            ),
          );
        }),
    ];
    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: cells,
    );
  }
}

class _DayDetails extends StatelessWidget {
  final DateTime day;
  const _DayDetails({required this.day});

  bool _same(DateTime a) => a.year == day.year && a.month == day.month && a.day == day.day;

  @override
  Widget build(BuildContext context) {
    final s = Store.instance;
    final list = <(IconData, String, String)>[
      for (final x in s.sessions.where((x) => _same(x.start)))
        (Icons.fitness_center, x.title, '${x.duration.inMinutes} min · ${x.kcal.round()} kcal'),
      for (final x in s.external.where((x) => _same(x.start)))
        (Icons.directions_run, '${x.sportLabel}: ${x.name}',
            '${x.minutes} min${x.km != null ? ' · ${x.km!.toStringAsFixed(1)} km' : ''}${x.avgHr != null ? ' · ${x.avgHr} bpm' : ''}'),
    ];
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Column(children: [
        for (final (icon, t, sub) in list)
          ListTile(dense: true, leading: Icon(icon), title: Text(t), subtitle: Text(sub, style: TextStyle(color: C.muted))),
      ]),
    );
  }
}

/// Mały pasek na ekranie głównym: seria, poziom, ostrzeżenie o zagrożonej serii.
class StreakStrip extends StatelessWidget {
  const StreakStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final s = Store.instance;
    final st = s.streaks;
    final lv = s.level;
    final risk = st.riskText;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CalendarScreen())),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            const Text('🔥', style: TextStyle(fontSize: 20)),
            const SizedBox(width: 6),
            Text('${st.dayStreak}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(risk ?? 'Tydzień: ${st.thisWeek}/${st.weekTarget} · poziom ${lv.level} (${lv.title.toLowerCase()})',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: risk != null ? C.warn : C.text, fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(value: lv.progress, minHeight: 5, backgroundColor: C.surface2, color: C.accent),
                ),
              ]),
            ),
            const Icon(Icons.chevron_right),
          ]),
        ),
      ),
    );
  }
}

/// Dla innych ekranów: czy aktywność z zewnątrz pochodzi z danego dnia.
bool sameDay(ExternalActivity x, DateTime d) => x.start.year == d.year && x.start.month == d.month && x.start.day == d.day;
