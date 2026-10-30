import 'dart:convert';

import 'package:koofr_backup_ui/koofr_backup_ui.dart';

import 'store.dart';

/// Kopia Formy na rodzinnym koncie Koofr (wspólny moduł z Rytmu Snu).
class FormaBackup extends BackupAdapter {
  @override
  String get appId => 'forma';

  @override
  String get appName => 'Forma';

  @override
  String get contentNote => 'W kopii: profil, historia treningów, samopoczucie, pomiary HRV i oceny ćwiczeń.';

  @override
  Future<BackupContent> export() async => BackupContent(utf8.encode(Store.instance.exportJson()));

  @override
  Future<void> import(RestoredBackup r, void Function(String step) progress) async {
    progress('Wczytuję dane…');
    Store.instance.importJson(utf8.decode(r.data));
    await Store.instance.save();
  }
}
