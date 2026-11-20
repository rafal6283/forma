import 'command.dart';
import 'health_sync.dart';
import 'library.dart';
import 'models.dart';
import 'store.dart';
import 'watch_hr.dart';
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
  await fillWatchHr();
}

/// Treningi z ostatnich 3 dni bez tętna z opaski: tętno z zegarka z Health Connect (zegarek synchronizuje się
/// z opóźnieniem, więc sprawdzamy przy każdym otwarciu). Zwraca liczbę uzupełnionych treningów.
Future<int> fillWatchHr({Session? only}) async {
  final s = Store.instance;
  if (!s.profile.healthConnect) return 0;
  final cutoff = DateTime.now().subtract(const Duration(days: 3));
  var n = 0;
  for (var i = 0; i < s.sessions.length; i++) {
    final x = s.sessions[i];
    if (only != null && x.id != only.id) continue;
    if (x.start.isBefore(cutoff) || x.hr.any((v) => v > 0)) continue;
    final samples = await HealthSync.instance.heartRate(x.start.subtract(const Duration(minutes: 3)), x.end);
    final w = WatchHr.fromSamples(samples, x.start, x.end, s.profile.maxHr);
    if (w == null || w.coverage < 0.3) continue;
    s.sessions[i] = w.apply(x);
    n++;
  }
  if (n > 0) await s.save();
  return n;
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
