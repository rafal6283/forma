import 'health_sync.dart';
import 'library.dart';
import 'store.dart';
import 'trainer.dart';

/// Trener zbudowany z aktualnych danych aplikacji.
Trainer coach() {
  final s = Store.instance;
  return Trainer(
    profile: s.profile,
    sessions: s.sessions,
    library: Library.instance.all,
    checkins: s.checkins,
    hrv: s.hrv,
    exScore: s.stats.map((k, v) => MapEntry(k, v.score)),
    exLast: {for (final e in s.stats.entries) if (e.value.last != null) e.key: e.value.last!},
    hidden: {for (final e in s.stats.entries) if (e.value.hidden) e.key},
    favorites: {for (final e in s.stats.entries) if (e.value.favorite) e.key},
    health: s.health,
  );
}

/// Odświeża dane z Health Connect (sen, tętno, HRV, waga), jeśli włączone.
Future<void> refreshHealth() async {
  final s = Store.instance;
  if (!s.profile.healthConnect) return;
  s.health = await HealthSync.instance.snapshot();
  s.touch();
}
