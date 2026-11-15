import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/library.dart';
import '../core/models.dart';
import '../core/store.dart';
import 'muscle_map.dart';
import 'theme.dart';

/// Obrazek podsumowania treningu do wysłania (komunikator, media społecznościowe).
class ShareCard extends StatelessWidget {
  final Session s;
  const ShareCard(this.s, {super.key});

  @override
  Widget build(BuildContext context) {
    final st = Store.instance.streaks;
    final lib = Library.instance;
    final top = <String, int>{};
    for (final d in s.done) {
      if (d.reps != null) top[d.exId] = (top[d.exId] ?? 0) + d.reps!;
    }
    final best = (top.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(3);
    Widget stat(String v, String l) => Column(children: [
          Text(v, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
          Text(l, style: const TextStyle(color: Colors.white60, fontSize: 11)),
        ]);
    return Container(
      width: 360,
      height: 520,
      padding: const EdgeInsets.all(22),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B1F2A), Color(0xFF2A1A16)],
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('FORMA', style: TextStyle(color: C.accent, fontWeight: FontWeight.w900, letterSpacing: 3)),
          const Spacer(),
          Text(fmtDate(s.start), style: const TextStyle(color: Colors.white60, fontSize: 12)),
        ]),
        const SizedBox(height: 10),
        Text(s.title, maxLines: 2, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
        const SizedBox(height: 14),
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          stat('${s.duration.inMinutes}', 'minut'),
          stat('${s.kcal.round()}', 'kcal'),
          if (s.avgHr != null) stat('${s.avgHr}', 'śr. tętno'),
          stat('🔥${st.dayStreak}', 'dni z rzędu'),
        ]),
        const SizedBox(height: 10),
        Expanded(child: Center(child: MuscleMap(muscleLoad(s.done), height: 210, legend: false))),
        for (final e in best)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Row(children: [
              Expanded(
                  child: Text(lib[e.key]?.name ?? e.key,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70))),
              Text('${e.value} powt.', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ]),
          ),
      ]),
    );
  }
}

/// Pokazuje kartę i udostępnia ją jako obrazek PNG.
Future<void> shareSessionCard(BuildContext context, Session s) async {
  final key = GlobalKey();
  await showDialog<void>(
    context: context,
    builder: (c) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        FittedBox(child: RepaintBoundary(key: key, child: ShareCard(s))),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () async {
            final b = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
            if (b == null) return;
            final img = await b.toImage(pixelRatio: 3);
            final png = await img.toByteData(format: ui.ImageByteFormat.png);
            if (png == null) return;
            final f = File('${(await getTemporaryDirectory()).path}/forma_${s.start.millisecondsSinceEpoch}.png');
            await f.writeAsBytes(png.buffer.asUint8List());
            await SharePlus.instance.share(ShareParams(files: [XFile(f.path)], text: '${s.title} — Forma'));
            if (c.mounted) Navigator.pop(c);
          },
          icon: const Icon(Icons.share),
          label: const Text('Udostępnij obrazek'),
        ),
      ]),
    ),
  );
}
