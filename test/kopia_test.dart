import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forma/core/backup.dart';
import 'package:forma/core/models.dart';
import 'package:forma/core/store.dart';
import 'package:koofr_backup_ui/testing.dart';

/// Kopia na Koofr → nowy telefon (tylko kod odzyskiwania) → przywrócenie: treningi wracają.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('forma');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (c) async => dir.path);
    HttpOverrides.global = null; // serwer WebDAV w pamięci potrzebuje prawdziwego HttpClient
  });

  test('przywrócenie kopii na czystym telefonie', () async {
    final s = Store.instance;
    await s.load();
    final start = DateTime(2026, 11, 19, 18);
    s.sessions.add(Session(
      id: 'w1',
      start: start,
      end: start.add(const Duration(minutes: 30)),
      kind: WorkoutKind.upper,
      title: 'Góra',
      done: const [],
      kcal: 240,
      rpe: 7,
    ));
    await s.save();
    final restored = await kopiaAdapteraNaNowyTelefon(FormaBackup());

    // „nowy telefon”: pusty katalog danych
    for (final f in dir.listSync()) {
      f.deleteSync(recursive: true);
    }
    await s.load();
    expect(s.sessions, isEmpty);

    await FormaBackup().import(restored, (_) {});
    expect(s.sessions.map((x) => x.id), ['w1']);
    expect(s.sessions.single.kcal, 240);
  });
}
