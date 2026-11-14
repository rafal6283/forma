import 'command.dart';
import 'health_sync.dart';
import 'library.dart';
import 'models.dart';
import 'store.dart';
import 'trainer.dart';

/// Trener zbudowany z aktualnych danych aplikacji.
Trainer coach({Profile? profile}) {
  final s = Store.instance;
  return Trainer(
    profile: profile ?? s.profile,
    sessions: s.sessions,
    library: Library.instance.all,
    checkins: s.checkins,
    hrv: s.hrv,
    exScore: s.stats.map((k, v) => MapEntry(k, v.score)),
    exLast: {for (final e in s.stats.entries) if (e.value.last != null) e.key: e.value.last!},
    hidden: {for (final e in s.stats.entries) if (e.value.hidden) e.key},
    favorites: {for (final e in s.stats.entries) if (e.value.favorite) e.key},
    health: s.health,
    external: s.external,
    factors: s.dayFactors,
  );
}

/// Odświeża dane z Health Connect (sen, tętno, HRV, waga), jeśli włączone.
Future<void> refreshHealth() async {
  final s = Store.instance;
  if (!s.profile.healthConnect) return;
  s.health = await HealthSync.instance.snapshot();
  s.touch();
}

/// Plan z polecenia zwykłym zdaniem.
WorkoutPlan planFromCommand(WorkoutCommand c) {
  final s = Store.instance;
  final p = Profile.fromJson(s.profile.toJson());
  if (c.equipment != null) p.equipment = c.equipment!;
  final t = coach(profile: p);
  final r = t.readiness();
  final kind = c.kind ?? t.recommendKind(r).$1;
  return t.generate(
    kind: kind,
    readiness: r,
    format: c.format,
    minutes: c.minutes,
    load: c.load,
    quiet: c.quiet,
    warmup: c.warmup,
    reason: 'Na Twoje polecenie: ${c.understood.join(', ')}.',
  );
}
