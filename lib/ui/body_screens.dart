import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../core/body_checks.dart';
import '../core/coach.dart';
import '../core/library.dart';
import '../core/models.dart';
import '../core/rep_counter.dart';
import '../core/sfx.dart';
import '../core/store.dart';
import '../core/voice.dart';
import 'insights.dart';
import 'pose_camera.dart';
import 'preview_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Sesja ćwiczeń na wskazane słabe miejsca (rozciąganie/mobilność).
WorkoutPlan focusPlan(String title, List<String> ids) {
  final lib = Library.instance;
  final items = <CustomItem>[
    for (final id in {...ids})
      if (lib[id] != null)
        lib[id]!.isStatic || lib[id]!.type == ExType.stretch || lib[id]!.type == ExType.mobility
            ? CustomItem(exId: id, seconds: 40, rest: 10)
            : CustomItem(exId: id, reps: 10, rest: 20),
  ];
  return coach().customPlan(CustomWorkout(id: 'focus', name: title, items: items, rounds: 2, roundRest: 20));
}

/// Ekran „Ciało”: test ruchomości, postawa, zdjęcia sylwetki i obwody.
class BodyHubScreen extends StatelessWidget {
  const BodyHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = Store.instance;
    final mob = s.mobility.isEmpty ? null : s.mobility.last;
    final pos = s.postures.isEmpty ? null : s.postures.last;
    Widget tile(IconData i, String t, String sub, Widget Function() page) => Card(
          child: ListTile(
            leading: Icon(i, color: C.accent),
            title: Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(sub, style: TextStyle(color: C.muted)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => page())),
          ),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Ciało')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
        tile(Icons.accessibility_new, 'Test ruchomości',
            mob == null ? 'Przysiad, ręce nad głową, skłon — kamerą, co miesiąc' : 'Ostatnio ${mob.score}/100 (${fmtDate(mob.at)})',
            () => const MobilityScreen()),
        tile(Icons.straighten, 'Postawa ze zdjęcia',
            pos == null ? 'Barki, miednica, głowa — zdjęcie przodem i bokiem' : 'Ostatnio ${fmtDate(pos.at)}',
            () => const PostureScreen()),
        tile(Icons.photo_camera_outlined, 'Zdjęcia sylwetki i obwody',
            '${s.photos.length} zdjęć · ${s.measurements.length} pomiarów', () => const ProgressPhotosScreen()),
      ]),
    );
  }
}

// ---------------------------------------------------------------- test ruchomości

class MobilityScreen extends StatefulWidget {
  const MobilityScreen({super.key});

  @override
  State<MobilityScreen> createState() => _MobilityScreenState();
}

class _MobilityScreenState extends State<MobilityScreen> {
  static const tests = [
    ('Przysiad', 'Bokiem do telefonu. Zejdź jak najniżej, pięty na podłodze, 3 razy.', 'squat'),
    ('Ręce nad głową', 'Bokiem. Proste ręce unieś jak najwyżej nad głowę, bez odchylania pleców, 3 razy.', 'overhead'),
    ('Skłon', 'Bokiem. Proste kolana, pochyl się jak najniżej w stronę stóp, 3 razy.', 'fold'),
  ];
  int step = -1; // -1 = wstęp, 0..2 test, 3 = wynik
  int secs = 0;
  Timer? timer;
  final vals = <double>[];
  final res = <String, double?>{};
  bool recording = false;

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  void _start(int i) {
    setState(() {
      step = i;
      vals.clear();
      recording = false;
      secs = 5;
    });
    Voice.instance.say(tests[i].$1);
    timer?.cancel();
    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() => secs--);
      if (!recording && secs <= 0) {
        recording = true;
        secs = 12;
        Fx.instance.play(Sfx.go);
        Voice.instance.say('Start');
      } else if (recording && secs <= 0) {
        t.cancel();
        Fx.instance.play(Sfx.set);
        final key = tests[i].$3;
        res[key] = extreme(vals, min: key != 'overhead');
        if (i < tests.length - 1) {
          _start(i + 1);
        } else {
          _finish();
        }
      } else if (!recording && secs <= 3) {
        Fx.instance.play(Sfx.tick);
      }
    });
  }

  Future<void> _finish() async {
    final r = MobilityResult(DateTime.now(), squatKnee: res['squat'], overhead: res['overhead'], fold: res['fold']);
    if (r.score != null) {
      Store.instance.mobility.add(r);
      await Store.instance.save();
    }
    if (mounted) setState(() => step = 3);
  }

  void _onPoints(Map<String, P3> p) {
    if (!recording || step < 0 || step > 2) return;
    final v = switch (tests[step].$3) { 'squat' => squatKneeAngle(p), 'overhead' => overheadAngle(p), _ => foldHipAngle(p) };
    if (v != null) vals.add(v);
  }

  @override
  Widget build(BuildContext context) {
    final hist = Store.instance.mobility;
    if (step >= 0 && step <= 2) {
      final t = tests[step];
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(title: Text('${step + 1}/3 · ${t.$1}')),
        body: Stack(fit: StackFit.expand, children: [
          PoseCamera(front: true, onPoints: _onPoints),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(16)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(recording ? 'Nagrywam… $secs s' : 'Przygotuj się: $secs',
                    style: TextStyle(color: recording ? C.good : Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(t.$2, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
              ]),
            ),
          ),
        ]),
      );
    }
    final last = hist.isEmpty ? null : hist.last;
    final prev = hist.length > 1 ? hist[hist.length - 2] : null;
    Widget row(String name, double? v, int Function(double) score, double? pv, String unit) {
      if (v == null) return ListTile(title: Text(name), trailing: Text('brak pomiaru', style: TextStyle(color: C.muted)));
      final sc = score(v);
      final d = pv == null ? null : sc - score(pv);
      return ListTile(
        title: Text(name),
        subtitle: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
              value: sc / 100, minHeight: 6, backgroundColor: C.surface2, color: sc >= 70 ? C.good : (sc >= 40 ? C.warn : C.bad)),
        ),
        trailing: SizedBox(
          width: 110,
          child: Text('$sc/100 · ${v.round()}$unit${d != null && d != 0 ? '\n${d > 0 ? '+' : ''}$d' : ''}',
              textAlign: TextAlign.right, style: TextStyle(color: C.muted, fontSize: 12)),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Test ruchomości')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
        Text(
          'Trzy krótkie testy przed kamerą (telefon oparty, Ty bokiem, cała sylwetka w kadrze). '
          'Mierzę kąty w stawach — rób test co miesiąc, żeby widzieć postęp. Dobre światło pomaga.',
          style: TextStyle(color: C.muted, height: 1.35),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: () => _start(0), icon: const Icon(Icons.videocam), label: const Text('Zacznij test')),
        if (last != null) ...[
          SectionTitle('Wynik ${fmtDate(last.at)}: ${last.score}/100'),
          Card(
            child: Column(children: [
              row('Głębokość przysiadu (kolano)', last.squatKnee, MobilityResult.squatScore, prev?.squatKnee, '°'),
              row('Ręce nad głową (bark)', last.overhead, MobilityResult.overheadScore, prev?.overhead, '°'),
              row('Skłon (biodro)', last.fold, MobilityResult.foldScore, prev?.fold, '°'),
            ]),
          ),
          if (hist.length > 1) ...[
            const SizedBox(height: 8),
            TrendLine([for (final h in hist) (h.score ?? 0).toDouble()]),
          ],
          if (last.focus.isNotEmpty) ...[
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => PreviewScreen(plan: focusPlan('Na słabe miejsca', last.focus)))),
              icon: const Icon(Icons.self_improvement),
              label: const Text('Ćwiczenia na słabe miejsca'),
            ),
          ],
        ],
      ]),
    );
  }
}

// ---------------------------------------------------------------- postawa

class PostureScreen extends StatefulWidget {
  const PostureScreen({super.key});

  @override
  State<PostureScreen> createState() => _PostureScreenState();
}

class _PostureScreenState extends State<PostureScreen> {
  int step = 0; // 0 wstęp, 1 zdjęcie przodem, 2 bokiem, 3 wynik
  final cam = PoseCameraController();
  PostureResult? frontR;
  bool busy = false;
  int countdown = 0;

  Future<void> _shoot() async {
    setState(() => busy = true);
    for (countdown = 5; countdown > 0; countdown--) {
      if (!mounted) return;
      setState(() {});
      Fx.instance.play(Sfx.tick);
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    final path = await cam.takePicture();
    if (path == null) {
      if (mounted) setState(() => busy = false);
      return;
    }
    Fx.instance.play(Sfx.set);
    final pts = await detectPoseInFile(path);
    try {
      File(path).deleteSync();
    } catch (_) {}
    if (!mounted) return;
    if (pts.length < 8) {
      toast(context, 'Nie widzę całej sylwetki — spróbuj jeszcze raz (cała postać w kadrze, dobre światło).');
      setState(() => busy = false);
      return;
    }
    if (step == 1) {
      frontR = PostureResult.front(pts);
      setState(() {
        step = 2;
        busy = false;
      });
      Voice.instance.say('Teraz bokiem');
    } else {
      final r = PostureResult.side(pts).merge(frontR ?? PostureResult(DateTime.now()));
      Store.instance.postures.add(r);
      await Store.instance.save();
      setState(() {
        step = 3;
        busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (step == 1 || step == 2) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(title: Text(step == 1 ? 'Zdjęcie przodem' : 'Zdjęcie bokiem'), actions: [
          IconButton(onPressed: cam.switchCamera, icon: const Icon(Icons.cameraswitch_outlined)),
        ]),
        body: Stack(fit: StackFit.expand, children: [
          PoseCamera(front: true, ctl: cam),
          if (countdown > 0)
            Center(
                child: Text('$countdown',
                    style: const TextStyle(fontSize: 120, color: Colors.white, fontWeight: FontWeight.w900))),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(
                step == 1
                    ? 'Stań przodem, swobodnie, ręce wzdłuż ciała, stopy na szerokość bioder.'
                    : 'Stań bokiem, swobodnie, patrz przed siebie.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: busy ? null : _shoot,
                icon: const Icon(Icons.timer_outlined),
                label: const Text('Zdjęcie za 5 s'),
              ),
            ]),
          ),
        ]),
      );
    }
    final hist = Store.instance.postures;
    final last = hist.isEmpty ? null : hist.last;
    return Scaffold(
      appBar: AppBar(title: const Text('Postawa')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
        Text(
          'Dwa zdjęcia: przodem i bokiem (telefon na wysokości pasa, 2–3 m dalej, samowyzwalacz). '
          'Zdjęcia są analizowane na telefonie i od razu kasowane — zostają tylko wyniki. To nie diagnoza; '
          'pomaga zauważyć nawyki (głowa w przód, zaokrąglone barki, nierówne barki lub miednica).',
          style: TextStyle(color: C.muted, height: 1.35),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
            onPressed: () => setState(() => step = 1), icon: const Icon(Icons.photo_camera), label: const Text('Zrób zdjęcia')),
        if (last != null) ...[
          SectionTitle('Wynik ${fmtDate(last.at)}'),
          Card(
            child: Column(children: [
              for (final (name, val, ok) in last.findings)
                ListTile(
                  dense: true,
                  leading: Icon(ok ? Icons.check_circle : Icons.info_outline, color: ok ? C.good : C.warn),
                  title: Text(name),
                  trailing: Text(val, style: TextStyle(color: C.muted)),
                ),
            ]),
          ),
          if (last.focus.isNotEmpty) ...[
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => PreviewScreen(plan: focusPlan('Postawa', last.focus)))),
              icon: const Icon(Icons.self_improvement),
              label: const Text('Ćwiczenia korygujące'),
            ),
          ],
        ],
      ]),
    );
  }
}

// ---------------------------------------------------------------- zdjęcia sylwetki i obwody

Future<Directory> _photoDir() async {
  final d = Directory('${(await getApplicationDocumentsDirectory()).path}/sylwetka');
  if (!d.existsSync()) d.createSync(recursive: true);
  return d;
}

class ProgressPhotosScreen extends StatefulWidget {
  const ProgressPhotosScreen({super.key});

  @override
  State<ProgressPhotosScreen> createState() => _ProgressPhotosScreenState();
}

class _ProgressPhotosScreenState extends State<ProgressPhotosScreen> {
  String? dir;
  String view = 'front';

  @override
  void initState() {
    super.initState();
    _photoDir().then((d) => setState(() => dir = d.path));
  }

  List<BodyPhoto> get photos => Store.instance.photos.where((p) => p.view == view).toList();

  Future<void> _new() async {
    final prev = photos.isEmpty ? null : '$dir/${photos.last.file}';
    final saved = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => _GhostCamera(ghost: prev, view: view, dir: dir!)));
    if (saved == true) setState(() {});
  }

  Future<void> _measure() async {
    final last = Store.instance.measurements.isEmpty ? null : Store.instance.measurements.last;
    final ctl = {for (final k in measureLabel.keys) k: TextEditingController(text: last?.values[k]?.toString() ?? '')};
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Pomiary'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final e in measureLabel.entries)
              TextField(
                controller: ctl[e.key],
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: e.value.$1, suffixText: e.value.$2),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Anuluj')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Zapisz')),
        ],
      ),
    );
    if (ok != true) return;
    final cm = <String, double>{};
    ctl.forEach((k, v) {
      final x = double.tryParse(v.text.replaceAll(',', '.'));
      if (x != null && x > 0) cm[k] = x;
    });
    if (cm.isEmpty) return;
    await Store.instance.addMeasurement(Measurement(DateTime.now(), cm));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ms = Store.instance.measurements;
    final list = photos;
    return Scaffold(
      appBar: AppBar(title: const Text('Sylwetka'), actions: [
        if (list.length > 1 && dir != null)
          IconButton(
            tooltip: 'Film postępu',
            icon: const Icon(Icons.slideshow),
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => _Timelapse(files: [for (final p in list) '$dir/${p.file}'], dates: [for (final p in list) p.at]))),
          ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: dir == null ? null : _new, icon: const Icon(Icons.add_a_photo), label: const Text('Zdjęcie')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 96), children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'front', label: Text('Przodem')),
            ButtonSegment(value: 'side', label: Text('Bokiem')),
            ButtonSegment(value: 'back', label: Text('Tyłem')),
          ],
          selected: {view},
          onSelectionChanged: (v) => setState(() => view = v.first),
        ),
        const SizedBox(height: 8),
        Text('Przy nowym zdjęciu zobaczysz poprzednie jako półprzezroczystą nakładkę — stań tak samo. '
            'Zdjęcia zostają tylko na telefonie.', style: TextStyle(color: C.muted, fontSize: 12)),
        const SizedBox(height: 8),
        if (dir != null && list.isNotEmpty)
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            childAspectRatio: 0.6,
            children: [
              for (final p in list.reversed)
                GestureDetector(
                  onLongPress: () async {
                    final del = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('Usunąć zdjęcie?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Nie')),
                          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Usuń')),
                        ],
                      ),
                    );
                    if (del != true) return;
                    try {
                      File('$dir/${p.file}').deleteSync();
                    } catch (_) {}
                    Store.instance.photos.remove(p);
                    await Store.instance.save();
                    setState(() {});
                  },
                  child: Stack(fit: StackFit.expand, children: [
                    ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.file(File('$dir/${p.file}'), fit: BoxFit.cover)),
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        color: Colors.black54,
                        child: Text(fmtDate(p.at), style: const TextStyle(color: Colors.white, fontSize: 11)),
                      ),
                    ),
                  ]),
                ),
            ],
          ),
        SectionTitle('Pomiary ciała', trailing: TextButton.icon(onPressed: _measure, icon: const Icon(Icons.add), label: const Text('Dodaj'))),
        if (ms.isEmpty)
          Text('Zmierz taśmą rano, na czczo — pas na wysokości pępka.', style: TextStyle(color: C.muted))
        else
          Card(
            child: Column(children: [
              for (final e in measureLabel.entries)
                if (ms.any((m) => m.values.containsKey(e.key)))
                  Builder(builder: (_) {
                    final v = [for (final m in ms) if (m.values[e.key] != null) m.values[e.key]!];
                    final d = v.last - v.first;
                    return ListTile(
                      dense: true,
                      title: Text(e.value.$1),
                      subtitle: v.length > 1 ? TrendLine(v, height: 28, color: C.calm) : null,
                      trailing: Text(
                          '${v.last.toStringAsFixed(1)} ${e.value.$2}${v.length > 1 ? '\n${d >= 0 ? '+' : ''}${d.toStringAsFixed(1)}' : ''}',
                          textAlign: TextAlign.right),
                    );
                  }),
            ]),
          ),
      ]),
    );
  }
}

class _GhostCamera extends StatefulWidget {
  final String? ghost;
  final String view, dir;
  const _GhostCamera({required this.ghost, required this.view, required this.dir});

  @override
  State<_GhostCamera> createState() => _GhostCameraState();
}

class _GhostCameraState extends State<_GhostCamera> {
  final cam = PoseCameraController();
  double opacity = 0.35;
  int countdown = 0;
  bool busy = false;

  Future<void> _shoot() async {
    setState(() => busy = true);
    for (countdown = 5; countdown > 0; countdown--) {
      if (!mounted) return;
      setState(() {});
      Fx.instance.play(Sfx.tick);
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    final path = await cam.takePicture();
    if (path == null || !mounted) return;
    final name = '${widget.view}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(path).copy('${widget.dir}/$name');
    try {
      File(path).deleteSync();
    } catch (_) {}
    Store.instance.photos.add(BodyPhoto(DateTime.now(), name, widget.view));
    await Store.instance.save();
    Fx.instance.play(Sfx.set);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(title: const Text('Nowe zdjęcie'), actions: [
          IconButton(onPressed: cam.switchCamera, icon: const Icon(Icons.cameraswitch_outlined)),
        ]),
        body: Stack(fit: StackFit.expand, children: [
          PoseCamera(
            front: false,
            ctl: cam,
            detect: false,
            overlay: widget.ghost == null
                ? null
                : Opacity(opacity: opacity, child: Image.file(File(widget.ghost!), fit: BoxFit.cover)),
          ),
          if (countdown > 0)
            Center(
                child: Text('$countdown', style: const TextStyle(fontSize: 120, color: Colors.white, fontWeight: FontWeight.w900))),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (widget.ghost != null)
                Row(children: [
                  const Text('Nakładka', style: TextStyle(color: Colors.white)),
                  Expanded(child: Slider(value: opacity, min: 0, max: 0.7, onChanged: (v) => setState(() => opacity = v))),
                ]),
              FilledButton.icon(
                  onPressed: busy ? null : _shoot, icon: const Icon(Icons.timer_outlined), label: const Text('Zdjęcie za 5 s')),
            ]),
          ),
        ]),
      );
}

class _Timelapse extends StatefulWidget {
  final List<String> files;
  final List<DateTime> dates;
  const _Timelapse({required this.files, required this.dates});

  @override
  State<_Timelapse> createState() => _TimelapseState();
}

class _TimelapseState extends State<_Timelapse> {
  int i = 0;
  Timer? t;

  @override
  void initState() {
    super.initState();
    t = Timer.periodic(const Duration(milliseconds: 700), (_) => setState(() => i = (i + 1) % widget.files.length));
  }

  @override
  void dispose() {
    t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(title: Text(fmtDate(widget.dates[i]))),
        body: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Image.file(File(widget.files[i]), key: ValueKey(i), fit: BoxFit.contain),
          ),
        ),
      );
}
