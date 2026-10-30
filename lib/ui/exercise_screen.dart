import 'package:flutter/material.dart';

import '../core/library.dart';
import '../core/models.dart';
import '../core/store.dart';
import 'figure_view.dart';
import 'muscle_map.dart';
import 'theme.dart';
import 'widgets.dart';

/// Biblioteka ćwiczeń z filtrami.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  ExType? type;
  String? group;
  String query = '';
  bool onlyAvailable = false;

  @override
  Widget build(BuildContext context) {
    final owned = Store.instance.profile.equipment;
    final list = Library.instance.all.where((e) {
      if (type != null && e.type != type) return false;
      if (group != null && !e.groups.contains(group) && !e.muscles.keys.any((m) => muscleLabel[m] == group)) return false;
      if (onlyAvailable && !e.availableWith(owned)) return false;
      if (query.isNotEmpty) {
        final q = query.toLowerCase();
        if (!e.name.toLowerCase().contains(q) && !e.groups.any((g) => g.contains(q))) return false;
      }
      return true;
    }).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Ćwiczenia')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Szukaj (nazwa lub partia, np. brzuch)',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: C.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              isDense: true,
            ),
            onChanged: (v) => setState(() => query = v.trim()),
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
            FilterChip(
              label: const Text('Mam sprzęt'),
              selected: onlyAvailable,
              onSelected: (v) => setState(() => onlyAvailable = v),
            ),
            const SizedBox(width: 8),
            ChoiceChip(label: const Text('Wszystkie'), selected: type == null, onSelected: (_) => setState(() => type = null)),
            for (final t in ExType.values) ...[
              const SizedBox(width: 8),
              ChoiceChip(label: Text(exTypeLabel[t]!), selected: type == t, onSelected: (_) => setState(() => type = t)),
            ],
          ]),
        ),
        SizedBox(
          height: 44,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
            ChoiceChip(label: const Text('Wszystkie partie'), selected: group == null, onSelected: (_) => setState(() => group = null)),
            for (final g in muscleGroups) ...[
              const SizedBox(width: 8),
              ChoiceChip(label: Text(g), selected: group == g, onSelected: (_) => setState(() => group = g)),
            ],
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('${list.length} ćwiczeń', style: const TextStyle(color: C.muted, fontSize: 12)),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: list.length,
            itemBuilder: (context, i) {
              final e = list[i];
              final st = Store.instance.stats[e.id];
              final ok = e.availableWith(owned);
              return Opacity(
                opacity: ok ? 1 : 0.5,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 4),
                  leading: FigureThumb(e),
                  title: Row(children: [
                    Flexible(child: Text(e.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                    if (st?.favorite == true) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.star, size: 16, color: C.warn)),
                    if (st?.hidden == true) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.block, size: 16, color: C.muted)),
                  ]),
                  subtitle: Text(
                    [
                      exTypeLabel[e.type]!,
                      e.groups.join(', '),
                      if (e.needsEquipment) e.eq.map((q) => q.split('|').map((x) => equipmentLabel[x] ?? x).join(' / ')).join(', '),
                    ].join(' · '),
                    style: const TextStyle(color: C.muted, fontSize: 12),
                  ),
                  trailing: LevelDots(e.lvl),
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => ExerciseScreen(exercise: e)));
                    setState(() {});
                  },
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

/// Szczegóły ćwiczenia z animacją.
class ExerciseScreen extends StatefulWidget {
  final Exercise exercise;
  const ExerciseScreen({super.key, required this.exercise});

  @override
  State<ExerciseScreen> createState() => _ExerciseScreenState();
}

class _ExerciseScreenState extends State<ExerciseScreen> {
  double speed = 1;

  @override
  Widget build(BuildContext context) {
    final e = widget.exercise;
    final store = Store.instance;
    final st = store.stat(e.id);
    final lib = Library.instance;
    final easier = e.easier == null ? null : lib[e.easier!];
    final harder = e.harder == null ? null : lib[e.harder!];
    return Scaffold(
      appBar: AppBar(title: Text(e.name), actions: [
        IconButton(
          tooltip: 'Ulubione — trener wybiera je częściej',
          icon: Icon(st.favorite ? Icons.star : Icons.star_border, color: st.favorite ? C.warn : null),
          onPressed: () async {
            setState(() => st.favorite = !st.favorite);
            await store.save();
          },
        ),
      ]),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
        Container(
          height: 300,
          decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(20)),
          padding: const EdgeInsets.all(12),
          child: FigureView(e, speed: speed),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (final s in [0.5, 1.0])
            Padding(
              padding: const EdgeInsets.all(6),
              child: ChoiceChip(
                label: Text(s == 1 ? 'Normalnie' : 'Wolno'),
                selected: speed == s,
                onSelected: (_) => setState(() => speed = s),
              ),
            ),
        ]),
        Wrap(spacing: 8, runSpacing: 8, children: [
          Chip(label: Text(exTypeLabel[e.type]!)),
          for (final g in e.groups) Chip(label: Text(g)),
          Chip(label: Row(mainAxisSize: MainAxisSize.min, children: [const Text('Poziom '), LevelDots(e.lvl)])),
          if (e.uni) const Chip(label: Text('na każdą stronę')),
          if (e.impact) const Chip(label: Text('ze skokami')),
        ]),
        if (e.muscles.isNotEmpty) ...[
          const SectionTitle('Mięśnie'),
          MuscleMap(e.muscles, height: 200),
        ],
        if (e.needsEquipment) ...[
          const SectionTitle('Sprzęt'),
          Text(e.eq.map((q) => q.split('|').map((x) => equipmentLabel[x] ?? x).join(' lub ')).join(', ')),
        ],
        if (e.tips.isNotEmpty) ...[
          const SectionTitle('Technika'),
          for (final t in e.tips)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Padding(padding: EdgeInsets.only(top: 2, right: 8), child: Icon(Icons.check, size: 18, color: C.good)),
                Expanded(child: Text(t, style: const TextStyle(fontSize: 15, height: 1.3))),
              ]),
            ),
        ],
        if (e.stress.isNotEmpty) ...[
          const SectionTitle('Uważaj'),
          Text('Obciąża: ${e.stress.join(', ')}. Przy dolegliwościach zaznacz je w ustawieniach — trener je pominie.',
              style: const TextStyle(color: C.muted)),
        ],
        if (easier != null || harder != null) ...[
          const SectionTitle('Progresja'),
          if (easier != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.arrow_downward, color: C.good),
              title: Text('Łatwiej: ${easier.name}'),
              onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ExerciseScreen(exercise: easier))),
            ),
          if (harder != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.arrow_upward, color: C.accent),
              title: Text('Trudniej: ${harder.name}'),
              onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ExerciseScreen(exercise: harder))),
            ),
        ],
        const SectionTitle('Twoje dane'),
        Text(st.count == 0
            ? 'Jeszcze nie wykonywane.'
            : 'Wykonane: ${st.count}×${st.last != null ? ', ostatnio ${fmtDate(st.last!)}' : ''}.'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Nie proponuj tego ćwiczenia'),
          value: st.hidden,
          onChanged: (v) async {
            setState(() => st.hidden = v);
            await store.save();
          },
        ),
      ]),
    );
  }
}
