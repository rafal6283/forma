import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../core/coach.dart';
import '../core/library.dart';
import '../core/models.dart';
import '../core/store.dart';
import 'figure_view.dart';
import 'preview_screen.dart';
import 'theme.dart';

String _newId() => 'c${DateTime.now().microsecondsSinceEpoch}';

/// Własne treningi: lista, start, udostępnianie i import kodu.
class CustomListScreen extends StatefulWidget {
  const CustomListScreen({super.key});

  @override
  State<CustomListScreen> createState() => _CustomListScreenState();
}

class _CustomListScreenState extends State<CustomListScreen> {
  final store = Store.instance;

  Future<void> _edit([CustomWorkout? w]) async {
    final res = await Navigator.push<CustomWorkout>(
        context, MaterialPageRoute(builder: (_) => CustomEditScreen(workout: w)));
    if (res == null) return;
    setState(() {
      final i = store.customs.indexWhere((c) => c.id == res.id);
      if (i >= 0) {
        store.customs[i] = res;
      } else {
        store.customs.add(res);
      }
    });
    await store.save();
  }

  Future<void> _share(CustomWorkout w) async {
    final code = customCode(w);
    await Clipboard.setData(ClipboardData(text: code));
    await SharePlus.instance.share(ShareParams(
      text: 'Trening „${w.name}” z Formy (${w.items.length} ćwiczeń × ${w.rounds}).\n'
          'W Formie: Moje treningi → Importuj kod i wklej:\n$code',
      subject: 'Trening „${w.name}”',
    ));
  }

  Future<void> _import() async {
    final clip = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    if (!mounted) return;
    final ctl = TextEditingController(text: clip.contains('FORMA1:') ? clip : '');
    final text = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Importuj trening'),
        content: TextField(
          controller: ctl,
          maxLines: 4,
          decoration: const InputDecoration(hintText: 'Wklej kod FORMA1:…'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Anuluj')),
          FilledButton(onPressed: () => Navigator.pop(c, ctl.text), child: const Text('Importuj')),
        ],
      ),
    );
    if (text == null || !mounted) return;
    final w = customFromCode(text, id: _newId(), known: Library.instance.byId.keys.toSet());
    if (w == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('To nie jest poprawny kod treningu.')));
      return;
    }
    setState(() => store.customs.add(w));
    await store.save();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Dodano „${w.name}”.')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Moje treningi'), actions: [
          IconButton(tooltip: 'Importuj kod', onPressed: _import, icon: const Icon(Icons.download_outlined)),
        ]),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _edit(),
          icon: const Icon(Icons.add),
          label: const Text('Nowy trening'),
        ),
        body: store.customs.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'Ułóż własny trening z katalogu: dodaj ćwiczenia, przeciągnij, żeby zmienić kolejność, '
                    'ustaw powtórzenia lub czas. Możesz go wysłać komuś jako kod.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: C.muted, height: 1.4),
                  ),
                ),
              )
            : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
                for (final w in store.customs)
                  Card(
                    child: ListTile(
                      leading: w.items.isEmpty || Library.instance[w.items.first.exId] == null
                          ? const Icon(Icons.fitness_center)
                          : FigureThumb(Library.instance[w.items.first.exId]!, size: 44),
                      title: Text(w.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(
                        '${w.items.length} ćwiczeń × ${w.rounds} · ok. ${coach().customPlan(w).minutes} min',
                        style: TextStyle(color: C.muted),
                      ),
                      onTap: () => Navigator.push(
                          context, MaterialPageRoute(builder: (_) => PreviewScreen(plan: coach().customPlan(w)))),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) async {
                          switch (v) {
                            case 'edit':
                              await _edit(w);
                            case 'share':
                              await _share(w);
                            case 'del':
                              setState(() => store.customs.remove(w));
                              await store.save();
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('Edytuj')),
                          PopupMenuItem(value: 'share', child: Text('Udostępnij kod')),
                          PopupMenuItem(value: 'del', child: Text('Usuń')),
                        ],
                      ),
                    ),
                  ),
              ]),
      );
}

/// Kreator: nazwa, rundy, lista ćwiczeń z przeciąganiem i dawkami.
class CustomEditScreen extends StatefulWidget {
  final CustomWorkout? workout;
  const CustomEditScreen({super.key, this.workout});

  @override
  State<CustomEditScreen> createState() => _CustomEditScreenState();
}

class _CustomEditScreenState extends State<CustomEditScreen> {
  late final CustomWorkout w = widget.workout == null
      ? CustomWorkout(id: _newId(), name: 'Mój trening')
      : CustomWorkout.fromJson(widget.workout!.toJson());
  late final name = TextEditingController(text: w.name);

  Future<void> _add() async {
    final picked = await showModalBottomSheet<List<Exercise>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _Picker(),
    );
    if (picked == null) return;
    setState(() {
      for (final e in picked) {
        w.items.add(e.isStatic || e.type == ExType.stretch || e.type == ExType.mobility || e.type == ExType.cardio
            ? CustomItem(exId: e.id, seconds: e.type == ExType.cardio ? 40 : 30, rest: 20)
            : CustomItem(exId: e.id, reps: 12, rest: 30));
      }
    });
  }

  Future<void> _dose(CustomItem it) async {
    var reps = it.reps;
    var secs = it.seconds;
    var rest = it.rest;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(Library.instance[it.exId]?.name ?? it.exId,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Powtórzenia')),
                  ButtonSegment(value: false, label: Text('Czas')),
                ],
                selected: {reps != null},
                onSelectionChanged: (v) => set(() => reps = v.first ? (reps ?? 12) : null),
              ),
              if (reps != null)
                _Stepper('Powtórzenia', reps!, 1, 50, 1, (v) => set(() => reps = v))
              else
                _Stepper('Czas pracy (s)', secs, 10, 180, 5, (v) => set(() => secs = v)),
              _Stepper('Przerwa po (s)', rest, 0, 180, 5, (v) => set(() => rest = v)),
              const SizedBox(height: 8),
              FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Gotowe')),
            ]),
          ),
        ),
      ),
    );
    setState(() {
      it.reps = reps;
      it.seconds = secs;
      it.rest = rest;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.workout == null ? 'Nowy trening' : 'Edycja'), actions: [
          TextButton(
            onPressed: w.items.isEmpty
                ? null
                : () {
                    w.name = name.text.trim().isEmpty ? 'Mój trening' : name.text.trim();
                    Navigator.pop(context, w);
                  },
            child: const Text('Zapisz'),
          ),
        ]),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _add,
          icon: const Icon(Icons.add),
          label: const Text('Dodaj ćwiczenia'),
        ),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: TextField(controller: name, decoration: const InputDecoration(labelText: 'Nazwa')),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              Expanded(child: _Stepper('Rundy', w.rounds, 1, 10, 1, (v) => setState(() => w.rounds = v))),
              Expanded(child: _Stepper('Przerwa rund (s)', w.roundRest, 0, 300, 15, (v) => setState(() => w.roundRest = v))),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: w.items.isEmpty
                ? Center(child: Text('Dodaj ćwiczenia z katalogu', style: TextStyle(color: C.muted)))
                : ReorderableListView.builder(
                    padding: const EdgeInsets.only(bottom: 96),
                    itemCount: w.items.length,
                    onReorder: (a, b) => setState(() {
                      if (b > a) b--;
                      w.items.insert(b, w.items.removeAt(a));
                    }),
                    itemBuilder: (context, i) {
                      final it = w.items[i];
                      final e = Library.instance[it.exId];
                      return ListTile(
                        key: ValueKey('$i-${it.exId}-${identityHashCode(it)}'),
                        leading: e == null ? const Icon(Icons.help_outline) : FigureThumb(e, size: 44),
                        title: Text(e?.name ?? it.exId),
                        subtitle: Text(
                          '${it.reps != null ? '${it.reps} powt.' : '${it.seconds} s'}${e?.uni == true ? ' na stronę' : ''}'
                          ' · przerwa ${it.rest} s',
                          style: TextStyle(color: C.muted),
                        ),
                        onTap: () => _dose(it),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => setState(() => w.items.removeAt(i)),
                          ),
                          ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle)),
                        ]),
                      );
                    },
                  ),
          ),
        ]),
      );
}

class _Stepper extends StatelessWidget {
  final String label;
  final int value, min, max, step;
  final ValueChanged<int> onChanged;
  const _Stepper(this.label, this.value, this.min, this.max, this.step, this.onChanged);

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: Text(label, style: TextStyle(color: C.muted))),
        IconButton(
          onPressed: value - step >= min ? () => onChanged(value - step) : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        SizedBox(width: 36, child: Text('$value', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
        IconButton(
          onPressed: value + step <= max ? () => onChanged(value + step) : null,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ]);
}

/// Wybór ćwiczeń z katalogu (wyszukiwanie, kilka naraz).
class _Picker extends StatefulWidget {
  const _Picker();

  @override
  State<_Picker> createState() => _PickerState();
}

class _PickerState extends State<_Picker> {
  String q = '';
  final sel = <Exercise>[];

  @override
  Widget build(BuildContext context) {
    final eq = Store.instance.profile.equipment;
    final list = Library.instance.all
        .where((e) => e.availableWith(eq) && (q.isEmpty || e.name.toLowerCase().contains(q.toLowerCase())))
        .toList();
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.85,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            autofocus: false,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Szukaj ćwiczenia'),
            onChanged: (v) => setState(() => q = v),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: list.length,
            itemBuilder: (_, i) {
              final e = list[i];
              final on = sel.contains(e);
              return ListTile(
                leading: FigureThumb(e, size: 40),
                title: Text(e.name),
                subtitle: Text(e.groups.join(', '), style: TextStyle(color: C.muted)),
                trailing: Icon(on ? Icons.check_circle : Icons.add_circle_outline, color: on ? C.accent : C.muted),
                onTap: () => setState(() => on ? sel.remove(e) : sel.add(e)),
              );
            },
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: sel.isEmpty ? null : () => Navigator.pop(context, sel),
                child: Text(sel.isEmpty ? 'Zaznacz ćwiczenia' : 'Dodaj (${sel.length})'),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
