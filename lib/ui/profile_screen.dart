import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/catalog.dart';
import '../core/library.dart';
import '../core/models.dart';
import '../core/store.dart';
import 'fit_test_screen.dart';
import 'muscle_map.dart';
import 'theme.dart';
import 'users.dart';
import 'widgets.dart';

/// „Ty”: dane osoby, pomiary ciała, obciążenie mięśni, podsumowanie.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String metric = 'weight';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Store.instance,
        builder: (context, _) {
          final s = Store.instance;
          final p = s.profile;
          final w = s.weight;
          final bmi = p.heightCm > 0 ? w / math.pow(p.heightCm / 100, 2) : null;
          final last = s.measurements.isEmpty ? null : s.measurements.last;
          final now = DateTime.now();
          final week = s.sessions.where((x) => now.difference(x.end).inDays < 7);
          final load = muscleLoad(
            [for (final x in week) ...x.done],
            weight: (d) => 1,
          );
          final total = s.sessions.fold(0, (a, x) => a + x.duration.inSeconds);
          final kcal = s.sessions.fold(0.0, (a, x) => a + x.kcal);
          final topEx = s.stats.entries.where((e) => e.value.count > 0).toList()
            ..sort((a, b) => b.value.count.compareTo(a.value.count));
          final points = [
            for (final m in s.measurements)
              if (m.values[metric] != null) (m.at, m.values[metric]!),
          ];

          return Scaffold(
            appBar: AppBar(title: const Text('Ty'), actions: [
              IconButton(
                tooltip: 'Osoby',
                icon: const Icon(Icons.group_outlined),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UsersScreen())),
              ),
            ]),
            body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
              InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => showUserSheet(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(children: [
                    UserAvatar(p.name, size: 56),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p.name.isEmpty ? 'Bez imienia' : p.name,
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                        Text('${p.age} lat · ${p.heightCm} cm · ${goalLabel[p.goal]}',
                            style: TextStyle(color: C.muted)),
                      ]),
                    ),
                    if (s.users.length > 1) Icon(Icons.swap_horiz, color: C.muted),
                  ]),
                ),
              ),
              SectionTitle('Ciało', trailing: TextButton.icon(
                onPressed: () => showMeasureSheet(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Pomiar'),
              )),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Stat('waga, kg', w.toStringAsFixed(1).replaceAll('.', ','))),
                      Expanded(child: Stat('BMI', bmi == null ? '–' : bmi.toStringAsFixed(1).replaceAll('.', ','),
                          color: bmi == null ? null : (bmi < 18.5 || bmi >= 30 ? C.warn : (bmi < 25 ? C.good : C.text)))),
                      Expanded(child: Stat('talia, cm', _v(last, 'waist'))),
                      Expanded(child: Stat('tłuszcz, %', _v(last, 'fat'))),
                    ]),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 36,
                      child: ListView(scrollDirection: Axis.horizontal, children: [
                        for (final e in measureLabel.entries)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              visualDensity: VisualDensity.compact,
                              label: Text(e.value.$1),
                              selected: metric == e.key,
                              onSelected: (_) => setState(() => metric = e.key),
                            ),
                          ),
                      ]),
                    ),
                    const SizedBox(height: 10),
                    if (points.length < 2)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          points.isEmpty
                              ? 'Dodaj pomiar, żeby śledzić zmiany${p.healthConnect ? ' (waga wczytuje się też z Health Connect)' : ''}.'
                              : 'Jeszcze jeden pomiar i pokażę wykres.',
                          style: TextStyle(color: C.muted),
                        ),
                      )
                    else
                      SizedBox(height: 140, child: _TrendChart(points, unit: measureLabel[metric]!.$2)),
                    if (s.measurements.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      TextButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const _MeasurementsList()),
                        ),
                        child: Text('Wszystkie pomiary (${s.measurements.length})'),
                      ),
                    ],
                  ]),
                ),
              ),
              SectionTitle('Forma', trailing: TextButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FitTestScreen())),
                child: const Text('Nowy test'),
              )),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: s.tests.isEmpty
                      ? Text('Zrób test formy, a zobaczysz tu wynik 0–100 i jego zmiany co miesiąc.',
                          style: TextStyle(color: C.muted))
                      : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Stat('wynik formy', '${s.tests.last.score}', color: C.readiness(s.tests.last.score))),
                            if (s.tests.length > 1)
                              Expanded(
                                child: Stat('zmiana',
                                    '${s.tests.last.score - s.tests[s.tests.length - 2].score >= 0 ? '+' : ''}${s.tests.last.score - s.tests[s.tests.length - 2].score}'),
                              ),
                            Expanded(child: Stat('testów', '${s.tests.length}')),
                          ]),
                          if (s.tests.length >= 2) ...[
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 110,
                              child: _TrendChart([for (final t in s.tests) (t.at, t.score.toDouble())], unit: 'pkt'),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Wrap(spacing: 6, runSpacing: 6, children: [
                            for (final e in s.tests.last.parts.entries)
                              Chip(visualDensity: VisualDensity.compact, label: Text('${e.key} ${e.value}')),
                          ]),
                        ]),
                ),
              ),
              const SectionTitle('Odznaki'),
              _Badges(list: badges(s)),
              const SectionTitle('Mięśnie w tym tygodniu'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: load.isEmpty
                      ? Text('Po pierwszym treningu zobaczysz tu, które mięśnie pracowały.',
                          style: TextStyle(color: C.muted))
                      : MuscleMap(load, height: 240),
                ),
              ),
              const SectionTitle('Od początku'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Stat('treningi', '${s.sessions.length}')),
                      Expanded(child: Stat('czas', fmtMin(total))),
                      Expanded(child: Stat('kcal', '${kcal.round()}')),
                      Expanded(child: Stat('poziom', p.level.toStringAsFixed(1).replaceAll('.', ','))),
                    ]),
                    if (topEx.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text('Najczęściej', style: TextStyle(color: C.muted)),
                      const SizedBox(height: 6),
                      for (final e in topEx.take(5))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(children: [
                            Expanded(child: Text(Library.instance[e.key]?.name ?? e.key)),
                            Text('${e.value.count}×', style: TextStyle(color: C.muted)),
                          ]),
                        ),
                    ],
                  ]),
                ),
              ),
            ]),
          );
        },
      );

  static String _v(Measurement? m, String k) {
    final v = m?.values[k];
    return v == null ? '–' : v.toStringAsFixed(1).replaceAll('.', ',');
  }
}

/// Dodanie pomiaru ciała.
Future<void> showMeasureSheet(BuildContext context) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _MeasureSheet(),
    );

class _MeasureSheet extends StatefulWidget {
  const _MeasureSheet();

  @override
  State<_MeasureSheet> createState() => _MeasureSheetState();
}

class _MeasureSheetState extends State<_MeasureSheet> {
  late final Map<String, TextEditingController> ctl = {
    for (final k in measureLabel.keys)
      k: TextEditingController(
          text: k == 'weight' ? Store.instance.weight.toStringAsFixed(1).replaceAll('.', ',') : ''),
  };

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Nowy pomiar', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('Wypełnij tylko to, co mierzysz. Obwody najlepiej rano, w tym samym miejscu.',
                  style: TextStyle(color: C.muted, fontSize: 12)),
              const SizedBox(height: 12),
              Wrap(spacing: 10, runSpacing: 10, children: [
                for (final e in measureLabel.entries)
                  SizedBox(
                    width: (MediaQuery.of(context).size.width - 42) / 2,
                    child: TextField(
                      controller: ctl[e.key],
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: e.value.$1,
                        suffixText: e.value.$2,
                        filled: true,
                        fillColor: C.surface2,
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
              ]),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () async {
                  final v = <String, double>{};
                  ctl.forEach((k, c) {
                    final x = double.tryParse(c.text.replaceAll(',', '.').trim());
                    if (x != null && x > 0) v[k] = x;
                  });
                  if (v.isNotEmpty) await Store.instance.addMeasurement(Measurement(DateTime.now(), v));
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('Zapisz'),
              ),
            ]),
          ),
        ),
      );
}

class _MeasurementsList extends StatelessWidget {
  const _MeasurementsList();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Store.instance,
        builder: (context, _) {
          final list = Store.instance.measurements.reversed.toList();
          return Scaffold(
            appBar: AppBar(title: const Text('Pomiary')),
            body: ListView(padding: const EdgeInsets.all(16), children: [
              for (final m in list)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(fmtDate(m.at)),
                    subtitle: Text(
                      m.values.entries
                          .map((e) =>
                              '${measureLabel[e.key]?.$1 ?? e.key} ${e.value.toStringAsFixed(1).replaceAll('.', ',')} ${measureLabel[e.key]?.$2 ?? ''}')
                          .join(' · '),
                      style: TextStyle(color: C.muted),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        if (await confirm(context, 'Usunąć pomiar?', fmtDate(m.at), ok: 'Usuń')) {
                          await Store.instance.deleteMeasurement(m);
                        }
                      },
                    ),
                  ),
                ),
            ]),
          );
        },
      );
}

/// Prosty wykres trendu (data → wartość).
class _TrendChart extends StatelessWidget {
  final List<(DateTime, double)> points;
  final String unit;
  const _TrendChart(this.points, {required this.unit});

  @override
  Widget build(BuildContext context) {
    final first = points.first.$2, last = points.last.$2;
    final d = last - first;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        '${d >= 0 ? '+' : ''}${d.toStringAsFixed(1).replaceAll('.', ',')} $unit od ${fmtDate(points.first.$1)}',
        style: TextStyle(color: d == 0 ? C.muted : C.text, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      Expanded(child: CustomPaint(painter: _TrendPainter(points), size: Size.infinite)),
    ]);
  }
}

class _TrendPainter extends CustomPainter {
  final List<(DateTime, double)> pts;
  _TrendPainter(this.pts);

  @override
  void paint(Canvas canvas, Size size) {
    final t0 = pts.first.$1.millisecondsSinceEpoch.toDouble();
    final t1 = math.max(pts.last.$1.millisecondsSinceEpoch.toDouble(), t0 + 1);
    var lo = pts.map((p) => p.$2).reduce(math.min);
    var hi = pts.map((p) => p.$2).reduce(math.max);
    if (hi - lo < 1) {
      lo -= 0.5;
      hi += 0.5;
    }
    Offset P((DateTime, double) p) => Offset(
          (p.$1.millisecondsSinceEpoch - t0) / (t1 - t0) * size.width,
          size.height - (p.$2 - lo) / (hi - lo) * (size.height - 8) - 4,
        );
    final path = Path()..moveTo(P(pts.first).dx, P(pts.first).dy);
    for (final p in pts.skip(1)) {
      path.lineTo(P(p).dx, P(p).dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = C.accent
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );
    for (final p in pts) {
      canvas.drawCircle(P(p), 3.5, Paint()..color = C.accent);
    }
  }

  @override
  bool shouldRepaint(_TrendPainter o) => o.pts != pts;
}

class _Badges extends StatelessWidget {
  final List<Achievement> list;
  const _Badges({required this.list});

  @override
  Widget build(BuildContext context) {
    final got = list.where((b) => b.earned).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text('$got z ${list.length}', style: TextStyle(color: C.muted)),
          ),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 0.8,
            children: [
              for (final b in list)
                Tooltip(
                  message: b.desc,
                  triggerMode: TooltipTriggerMode.tap,
                  child: Opacity(
                    opacity: b.earned ? 1 : 0.3,
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(b.icon, style: const TextStyle(fontSize: 30)),
                      const SizedBox(height: 4),
                      Text(b.name,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          style: TextStyle(fontSize: 11, color: b.earned ? C.text : C.muted)),
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
