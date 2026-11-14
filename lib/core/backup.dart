import 'dart:convert';

import 'package:koofr_backup_ui/koofr_backup_ui.dart';

import 'exchange.dart';
import 'store.dart';

/// Kopia Formy na rodzinnym koncie Koofr (wspólny moduł z Rytmu Snu).
class FormaBackup extends BackupAdapter {
  @override
  String get appId => 'forma';

  @override
  String get appName => 'Forma';

  @override
  String get contentNote => 'W kopii: wszystkie osoby — profile, treningi, pomiary ciała, samopoczucie, HRV i oceny ćwiczeń.';

  @override
  ExchangeAdapter? get exchange => FormaExchange();

  @override
  Future<BackupContent> export() async => BackupContent(utf8.encode(await Store.instance.exportAll()));

  @override
  Future<void> import(RestoredBackup r, void Function(String step) progress) async {
    progress('Wczytuję dane…');
    await Store.instance.importAll(utf8.decode(r.data));
  }
}
