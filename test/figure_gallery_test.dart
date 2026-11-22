import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forma/core/library.dart';
import 'package:forma/core/scene.dart';
import 'package:forma/ui/figure3d.dart';

/// Galeria klatek animacji (do oglądania bez telefonu): FIGURY=<katalog> [FIGURY_IDS=a,b,c|all].
/// Dla każdego ćwiczenia: 4 fazy ruchu × 3 kamery (widok z aplikacji, miniatura z ukosa, obrót 3D).
void main() {
  final dir = Platform.environment['FIGURY'];
  test('galeria figur', () async {
    final lib = Library.parse(File('assets/exercises.json').readAsStringSync());
    final idsEnv = Platform.environment['FIGURY_IDS'] ?? '';
    final all = idsEnv == 'all';
    final ids = all ? [for (final e in lib.all) e.id] : idsEnv.split(',').where((s) => s.isNotEmpty).toList();
    final tile = all ? 180.0 : 300.0;
    Directory(dir!).createSync(recursive: true);
    for (final id in ids) {
      final ex = lib.all.firstWhere((e) => e.id == id);
      final a = ex.anim;
      final sc = Scene(a);
      final samples = [for (var i = 0; i <= 24; i++) sc.frameAt(a.cycle * i / 24).$2];
      var cx = 0.0;
      for (final j in samples) {
        cx += j['hip'].dx / samples.length;
      }
      final cams = [
        Cam(a.cam ?? 0, 0.08, cx, 0),
        Cam(a.cam ?? -0.35, 0.14, cx, 0),
        Cam((a.cam ?? 0) + 0.9, 0.2, cx, 0),
      ];
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec);
      canvas.drawRect(Rect.fromLTWH(0, 0, tile * 4, tile * 3), Paint()..color = const Color(0xFF15181F));
      for (var r = 0; r < 3; r++) {
        final cam = cams[r];
        final bounds = frame3d(samples, cam, floor: !a.hands);
        for (var c = 0; c < 4; c++) {
          final t = a.cycle * c / 4;
          final (_, j) = sc.frameAt(t);
          canvas.save();
          canvas.translate(c * tile, r * tile);
          canvas.clipRect(Rect.fromLTWH(0, 0, tile, tile));
          Figure3DPainter(
            j: j,
            cam: cam,
            bounds: bounds,
            hands: a.hands,
            hold: ex.hold,
            props: [for (final p in sc.props) Prop3(p.type, p.rect)],
          ).paint(canvas, Size(tile, tile));
          canvas.restore();
        }
      }
      final img = await rec.endRecording().toImage((tile * 4).round(), (tile * 3).round());
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      File('$dir/$id.png').writeAsBytesSync(png!.buffer.asUint8List());
    }
  }, skip: dir == null ? 'bez FIGURY=<katalog>' : false, timeout: const Timeout(Duration(minutes: 20)));
}
