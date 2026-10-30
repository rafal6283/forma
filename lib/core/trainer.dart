import 'dart:math' as math;

import 'models.dart';

/// Czynnik wpływający na gotowość — do pokazania użytkownikowi.
class Factor {
  final String label;
  final String value;
  final int effect; // punkty dodane/odjęte
  const Factor(this.label, this.value, this.effect);
}

class Readiness {
  final int score;
  final List<Factor> factors;
  final bool hasData;
  const Readiness(this.score, this.factors, this.hasData);

  String get tier => score < 40
      ? 'Regeneracja'
      : score < 60
          ? 'Lżej'
          : score < 80
              ? 'Normalnie'
              : 'Pełna moc';
}

/// Lokalny trener: ocenia gotowość, dobiera trening, uczy się z ocen po treningu.
class Trainer {
  final Profile profile;
  final List<Session> sessions;
  final List<CheckIn> checkins;
  final List<HrvMeasure> hrv;
  final Map<String, int> exScore; // ocena ćwiczeń: + za trudne, - za łatwe
  final Map<String, DateTime> exLast;
  final Set<String> hidden;
  final Set<String> favorites;
  final HealthSnapshot health;
  final List<Exercise> library;
  final DateTime now;

  Trainer({
    required this.profile,
    required this.sessions,
    required this.library,
    this.checkins = const [],
    this.hrv = const [],
    this.exScore = const {},
    this.exLast = const {},
    this.hidden = const {},
    this.favorites = const {},
    this.health = HealthSnapshot.empty,
    DateTime? now,
  }) : now = now ?? DateTime.now();

  // ---------------------------------------------------------------- gotowość

  CheckIn? get _today {
    for (final c in checkins.reversed) {
      if (c.at.year == now.year && c.at.month == now.month && c.at.day == now.day) return c;
    }
    return null;
  }

  Readiness readiness() {
    var score = 70.0;
    final f = <Factor>[];
    var data = false;

    // sen
    final sleep = health.sleepHours ?? _today?.sleepHours;
    if (sleep != null && sleep > 0) {
      data = true;
      final e = ((sleep - 7) * 6).clamp(-20, 10).round();
      score += e;
      f.add(Factor('Sen', _hm(sleep), e));
    }

    // tętno spoczynkowe względem własnej normy
    final hrHist = [
      ...health.restingHrHistory,
      ...hrv.where((h) => now.difference(h.at).inDays < 21 && h.restHr > 0).map((h) => h.restHr),
    ];
    final todayHrv = hrv.where((h) => now.difference(h.at).inHours < 20).toList();
    final rest = health.restingHr ?? (todayHrv.isNotEmpty ? todayHrv.last.restHr : null);
    if (rest != null && rest > 0 && hrHist.length >= 4) {
      data = true;
      final base = _median(hrHist.map((e) => e.toDouble()).toList());
      final d = rest - base;
      final e = (-d * 2).clamp(-15, 8).round();
      score += e;
      f.add(Factor('Tętno spoczynkowe', '$rest (norma ${base.round()})', e));
    }

    // HRV (ln RMSSD) względem ostatnich tygodni
    final hrvVals = [
      ...health.hrvHistory,
      ...hrv.where((h) => now.difference(h.at).inDays < 30).map((h) => h.rmssd),
    ].where((v) => v > 0).toList();
    final hrvToday = todayHrv.isNotEmpty ? todayHrv.last.rmssd : health.hrv;
    if (hrvToday != null && hrvToday > 0 && hrvVals.length >= 5) {
      data = true;
      final lns = hrvVals.map(math.log).toList();
      final mean = lns.reduce((a, b) => a + b) / lns.length;
      final sd = math.sqrt(lns.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) / lns.length);
      final z = (math.log(hrvToday) - mean) / math.max(sd, 0.05);
      final e = (z * 6).clamp(-15, 10).round();
      score += e;
      f.add(Factor('HRV', '${hrvToday.round()} ms', e));
    }

    // samopoczucie i zakwasy
    final c = _today;
    if (c != null) {
      data = true;
      final e = (c.feel - 3) * 7;
      score += e;
      f.add(Factor('Samopoczucie', const ['', 'kiepskie', 'słabe', 'zwykłe', 'dobre', 'świetne'][c.feel], e));
      if (c.sore.isNotEmpty) {
        final s = -math.min(12, c.sore.length * 3);
        score += s;
        f.add(Factor('Zakwasy', c.sore.join(', '), s));
      }
    }

    // obciążenie: ostatnie 7 dni względem średniej z 4 tygodni
    final acute = _load(7);
    final chronic = _load(28) / 4;
    if (chronic > 30 && acute > 0) {
      final r = acute / chronic;
      final e = r > 1.5 ? -12 : r > 1.3 ? -6 : r < 0.8 ? 4 : 0;
      if (e != 0) {
        score += e;
        f.add(Factor('Obciążenie tygodnia', '${(r * 100).round()}% normy', e));
      }
    }

    // przerwa od ostatniego treningu
    final last = sessions.isEmpty ? null : sessions.last;
    if (last != null) {
      final h = now.difference(last.end).inHours;
      final e = h < 12 ? -8 : h < 24 ? -3 : h >= 48 ? 3 : 0;
      if (e != 0) {
        score += e;
        f.add(Factor('Ostatni trening', h < 24 ? '$h h temu' : '${(h / 24).floor()} dni temu', e));
      }
      if (h < 48 && last.rpe >= 9) {
        score -= 5;
        f.add(const Factor('Ostatni trening', 'bardzo ciężki', -5));
      }
    }

    return Readiness(score.clamp(5, 100).round(), f, data);
  }

  double _load(int days) => sessions
      .where((s) => now.difference(s.end).inDays < days)
      .fold(0.0, (a, s) => a + s.load);

  /// Zmęczenie grup mięśniowych z ostatnich 3 dni (0 = świeże).
  Map<String, double> fatigue() {
    final out = {for (final g in muscleGroups) g: 0.0};
    final byId = {for (final e in library) e.id: e};
    for (final s in sessions) {
      final h = now.difference(s.end).inMinutes / 60;
      if (h > 96) continue;
      final decay = math.exp(-h / 36);
      for (final d in s.done) {
        final e = byId[d.exId];
        if (e == null || e.type == ExType.stretch || e.type == ExType.warmup) continue;
        final groups = e.groups.contains('całe ciało') ? muscleGroups : e.groups;
        for (final g in groups) {
          if (out.containsKey(g)) out[g] = out[g]! + d.seconds / 60 * s.rpe / 10 * decay / groups.length * 3;
        }
      }
    }
    return out;
  }

  // ---------------------------------------------------------------- wybór treningu

  static const _kindGroups = {
    WorkoutKind.fullBody: ['nogi', 'klatka', 'plecy', 'pośladki', 'barki', 'brzuch'],
    WorkoutKind.upper: ['klatka', 'plecy', 'barki', 'ramiona'],
    WorkoutKind.lower: ['nogi', 'pośladki'],
    WorkoutKind.back: ['plecy', 'barki', 'plecy'],
    WorkoutKind.arms: ['ramiona', 'barki', 'ramiona'],
    WorkoutKind.core: ['brzuch', 'plecy'],
    WorkoutKind.hiit: ['całe ciało', 'nogi', 'brzuch'],
    WorkoutKind.mobility: ['plecy', 'nogi', 'barki'],
    WorkoutKind.stretch: ['nogi', 'plecy'],
  };

  static const _goalRotation = {
    Goal.general: [WorkoutKind.fullBody, WorkoutKind.upper, WorkoutKind.lower, WorkoutKind.core, WorkoutKind.back,
      WorkoutKind.hiit],
    Goal.strength: [WorkoutKind.upper, WorkoutKind.lower, WorkoutKind.back, WorkoutKind.fullBody, WorkoutKind.arms,
      WorkoutKind.core],
    Goal.burn: [WorkoutKind.hiit, WorkoutKind.fullBody, WorkoutKind.lower, WorkoutKind.hiit, WorkoutKind.upper],
    Goal.fitness: [WorkoutKind.hiit, WorkoutKind.fullBody, WorkoutKind.core, WorkoutKind.lower],
    Goal.mobility: [WorkoutKind.mobility, WorkoutKind.core, WorkoutKind.stretch, WorkoutKind.fullBody],
  };

  /// Rodzaj treningu na dziś + powód.
  (WorkoutKind, String) recommendKind(Readiness r) {
    if (r.score < 40) {
      return (WorkoutKind.mobility, 'Organizm prosi o odpoczynek, więc dziś mobilność i spokojny ruch.');
    }
    final fat = fatigue();
    final lastKind = sessions.isEmpty ? null : sessions.last.kind;
    final options = _goalRotation[profile.goal]!;
    WorkoutKind? best;
    var bestScore = double.infinity;
    for (final k in options.toSet()) {
      if (k == lastKind && options.toSet().length > 1) continue;
      if (k == WorkoutKind.hiit && (r.score < 55 || _jumpsOff)) {
        if (profile.goal != Goal.burn && profile.goal != Goal.fitness) continue;
      }
      final groups = _kindGroups[k]!.where(fat.containsKey).toList();
      final f = groups.isEmpty ? 0.0 : groups.map((g) => fat[g]!).reduce(math.max);
      // preferencja: im wcześniej w rotacji celu, tym lepiej
      final rank = options.indexOf(k) * 0.4;
      final s = f + rank;
      if (s < bestScore) {
        bestScore = s;
        best = k;
      }
    }
    best ??= WorkoutKind.fullBody;
    final tired = fat.entries.where((e) => e.value > 2).map((e) => e.key).toList();
    final why = tired.isEmpty
        ? '${kindLabel[best]} — zgodnie z Twoim celem (${goalLabel[profile.goal]!.toLowerCase()}).'
        : 'Ostatnio pracowały: ${tired.join(', ')}. Dziś ${kindLabel[best]!.toLowerCase()}, żeby one odpoczęły.';
    return (best, why);
  }

  bool get _jumpsOff => profile.noJumping || profile.limits.contains('kolana');

  // ---------------------------------------------------------------- formaty

  /// Format pasujący do rodzaju treningu i celu; rotacja, żeby nie powtarzać ostatniego.
  WorkoutFormat recommendFormat(WorkoutKind kind, Readiness r) {
    if (kind == WorkoutKind.mobility || kind == WorkoutKind.stretch) return WorkoutFormat.flow;
    final opts = switch (profile.goal) {
      Goal.strength => [WorkoutFormat.sets, WorkoutFormat.supersets, WorkoutFormat.strengthIntervals],
      Goal.burn => [WorkoutFormat.hiit, WorkoutFormat.tabata, WorkoutFormat.circuit],
      Goal.fitness => [WorkoutFormat.circuit, WorkoutFormat.hiit, WorkoutFormat.strengthIntervals, WorkoutFormat.tabata],
      Goal.mobility => [WorkoutFormat.circuit, WorkoutFormat.strengthIntervals],
      Goal.general => [WorkoutFormat.circuit, WorkoutFormat.strengthIntervals, WorkoutFormat.sets, WorkoutFormat.tabata],
    };
    var list = [...opts];
    if (kind == WorkoutKind.hiit) list = [WorkoutFormat.hiit, WorkoutFormat.tabata];
    if (r.score < 55) list.removeWhere((f) => f == WorkoutFormat.tabata || f == WorkoutFormat.hiit);
    if (list.isEmpty) list = [WorkoutFormat.circuit];
    final recent = sessions.reversed.take(3).map((s) => s.format).toList();
    for (final f in list) {
      if (!recent.contains(f)) return f;
    }
    return list.first;
  }

  // ---------------------------------------------------------------- objętość tygodnia

  /// Docelowa liczba serii na partię w tygodniu.
  int get weeklySetTarget => switch (profile.goal) {
        Goal.strength => 12,
        Goal.general => 8,
        Goal.fitness || Goal.burn => 6,
        Goal.mobility => 4,
      };

  /// Serie na partię od poniedziałku (każde ćwiczenie w rundzie lub serii = 1 seria).
  Map<String, int> weeklySets({DateTime? at}) {
    final d = at ?? now;
    final monday = DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));
    final byId = {for (final e in library) e.id: e};
    final out = {for (final g in muscleGroups) g: 0};
    for (final s in sessions.where((s) => !s.start.isBefore(monday) && s.start.isBefore(monday.add(const Duration(days: 7))))) {
      for (final it in s.done) {
        final e = byId[it.exId];
        if (e == null || it.side == 2) continue;
        if (!{ExType.strength, ExType.core, ExType.cardio}.contains(e.type)) continue;
        final groups = e.groups.contains('całe ciało') ? muscleGroups : e.groups;
        for (final g in groups) {
          if (out.containsKey(g)) out[g] = out[g]! + 1;
        }
      }
    }
    return out;
  }

  // ---------------------------------------------------------------- progresja z historii

  /// Serie ćwiczenia z ostatniego treningu, w którym było robione.
  List<DoneItem> lastSets(String exId) {
    for (final s in sessions.reversed) {
      final l = s.done.where((d) => d.exId == exId).toList();
      if (l.isNotEmpty) return l;
    }
    return const [];
  }

  int? _lastFeedback(String exId) {
    for (final s in sessions.reversed) {
      if (s.done.any((d) => d.exId == exId)) return s.feedback[exId] ?? 0;
    }
    return null;
  }

  /// Cel powtórzeń: z ostatnich serii (+1, gdy wszystkie zrobione; −1, gdy za trudne), inaczej z poziomu.
  int repsTarget(Exercise e, double level, {double load = 1}) {
    final hist = lastSets(e.id).where((d) => d.reps != null && d.side != 2).toList();
    int base;
    if (hist.isEmpty) {
      base = (10 + (level - e.lvl) * 3).round().clamp(5, 20);
      if (e.type == ExType.cardio) base = (base * 1.5).round();
    } else {
      final target = hist.map((d) => d.target ?? d.reps!).reduce(math.max);
      final allHit = hist.every((d) => d.reps! >= (d.target ?? d.reps!));
      final minDone = hist.map((d) => d.reps!).reduce(math.min);
      final fb = _lastFeedback(e.id) ?? 0;
      if (fb > 0 || !allHit) {
        base = fb > 0 ? math.min(target - 1, minDone) : math.max(minDone, target - 1);
      } else {
        base = target + (fb < 0 ? 2 : 1);
      }
    }
    if (load < 0.95) base = (base * 0.8).round();
    return base.clamp(3, 30);
  }

  /// Czas utrzymania (ćwiczenia statyczne) z ostatniego treningu.
  int holdTarget(Exercise e, int fallback, {double load = 1}) {
    final hist = lastSets(e.id).where((d) => d.reps == null && d.side != 2).toList();
    var t = fallback;
    if (hist.isNotEmpty) {
      final best = hist.map((d) => d.seconds).reduce(math.max);
      final fb = _lastFeedback(e.id) ?? 0;
      t = fb > 0 ? best - 5 : best + 5;
    }
    if (load < 0.95) t = (t * 0.8).round();
    return t.clamp(15, 120);
  }

  /// Gdy cel powtórzeń jest duży, a jest trudniejsza wersja — podpowiedź zmiany.
  Exercise? progressionFor(Exercise e, int reps) {
    if (reps < 20 || e.harder == null) return null;
    final h = library.where((x) => x.id == e.harder).toList();
    return h.isEmpty ? null : h.first;
  }

  // ---------------------------------------------------------------- generator

  WorkoutPlan generate({
    required WorkoutKind kind,
    required Readiness readiness,
    WorkoutFormat? format,
    int? minutes,
    int seed = 0,
    String? reason,
    double load = 1,
    String? programDay,
  }) {
    final rnd = math.Random(seed == 0 ? now.millisecondsSinceEpoch : seed);
    final fmt = format ?? recommendFormat(kind, readiness);
    final total = (minutes ?? profile.minutes) * 60;
    final r = readiness.score;
    final adj = r < 40 ? -1.5 : r < 60 ? -0.7 : r >= 80 ? 0.3 : 0.0;
    final target = (profile.level + adj + (load - 1) * 2).clamp(1.0, 5.0);
    final calm = fmt == WorkoutFormat.flow || kind == WorkoutKind.mobility || kind == WorkoutKind.stretch;
    final repsMode = fmt == WorkoutFormat.sets || fmt == WorkoutFormat.supersets;

    final usable = library.where((e) {
      if (hidden.contains(e.id)) return false;
      if (!e.availableWith(profile.equipment)) return false;
      if (e.stress.any(profile.limits.contains)) return false;
      if (e.impact && (_jumpsOff || r < 45)) return false;
      return true;
    }).toList();

    final used = <String>{};
    double score(Exercise e) {
      var s = -(e.lvl - target).abs() * 1.6;
      if (e.lvl > target + 1) s -= 2;
      final fb = exScore[e.id] ?? 0;
      if (fb > 0 && e.lvl >= target) s -= fb * 0.8;
      if (fb < 0 && e.lvl <= target) s += fb * 0.6;
      final last = exLast[e.id];
      if (last != null && now.difference(last).inHours < 48) s -= 1.2;
      if (favorites.contains(e.id)) s += 1;
      if (e.needsEquipment) s += 0.8;
      // w seriach na powtórzenia unikamy ćwiczeń na czas (deski) i skoków
      if (repsMode && (e.isStatic || e.impact)) s -= 3;
      return s + rnd.nextDouble() * 1.4;
    }

    Exercise? pick(bool Function(Exercise) ok) {
      final c = usable.where((e) => ok(e) && !used.contains(e.id)).toList();
      if (c.isEmpty) return null;
      c.sort((a, b) => score(b).compareTo(score(a)));
      used.add(c.first.id);
      return c.first;
    }

    final items = <PlanItem>[];
    void add(Exercise e, int work, int rest, Phase p, {int round = 1, int rounds = 1, int? reps, String? tag}) {
      if (e.uni) {
        final half = reps != null ? work : math.max(15, work ~/ 2 + (e.isStatic ? 5 : 0));
        items.add(PlanItem(exId: e.id, work: half, rest: 5, phase: p, side: 1, round: round, rounds: rounds, reps: reps, tag: tag));
        items.add(PlanItem(exId: e.id, work: half, rest: rest, phase: p, side: 2, round: round, rounds: rounds, reps: reps, tag: tag));
      } else {
        items.add(PlanItem(exId: e.id, work: work, rest: rest, phase: p, round: round, rounds: rounds, reps: reps, tag: tag));
      }
    }

    // --- rozgrzewka
    final warmSec = calm ? 0 : math.max(150, (total * 0.12).round());
    if (warmSec > 0) {
      final n = (warmSec / 30).round().clamp(4, 7);
      final warm = <Exercise>[];
      for (var i = 0; i < n; i++) {
        final e = pick((e) =>
            (e.type == ExType.warmup || (e.type == ExType.cardio && e.lvl <= 2) || e.type == ExType.mobility) &&
            e.lvl <= math.max(2, target.round()) &&
            !e.needsEquipment);
        if (e != null) warm.add(e);
      }
      warm.sort((a, b) => a.met.compareTo(b.met));
      for (final e in warm) {
        add(e, 30, 0, Phase.warmup);
      }
    }

    // --- wyciszenie
    final coolSec = calm ? 0 : math.max(120, (total * 0.10).round());
    final cool = <Exercise>[];
    if (coolSec > 0) {
      final cg = _kindGroups[kind]!;
      final n = (coolSec / 40).round().clamp(3, 5);
      for (var i = 0; i < n; i++) {
        final g = cg[i % cg.length];
        final e = pick((e) => e.type == ExType.stretch && (e.groups.contains(g) || i >= cg.length)) ??
            pick((e) => e.type == ExType.stretch);
        if (e != null) cool.add(e);
      }
    }

    // partie z najmniejszą liczbą serii w tym tygodniu idą pierwsze
    final week = weeklySets();
    final groups = [..._kindGroups[kind]!]
      ..sort((a, b) => (week[a] ?? 0).compareTo(week[b] ?? 0));

    Exercise? pickFor(String g, {bool cardio = false}) {
      if (cardio) return pick((e) => e.type == ExType.cardio);
      if (kind == WorkoutKind.core) {
        return pick((e) => e.type == ExType.core || (e.type == ExType.strength && e.groups.contains('brzuch'))) ??
            pick((e) => e.groups.contains('plecy') && e.type == ExType.strength);
      }
      if (g == 'całe ciało') return pick((e) => e.type == ExType.cardio || e.groups.contains('całe ciało'));
      return pick((e) => (e.type == ExType.strength || e.type == ExType.core) && e.groups.contains(g)) ??
          pick((e) => e.type == ExType.strength && e.groups.any(groups.contains));
    }

    List<Exercise> pickList(int n, {bool alternateCardio = false}) {
      final list = <Exercise>[];
      for (var i = 0; i < n; i++) {
        Exercise? e;
        if (alternateCardio && i.isEven) {
          e = pickFor('', cardio: true);
        } else {
          e = pickFor(groups[i % groups.length]);
        }
        e ??= pick((e) => e.type == ExType.strength || e.type == ExType.core || e.type == ExType.cardio);
        if (e != null) list.add(e);
      }
      return list;
    }

    final mainSec = total - items.fold(0, (s, i) => s + i.work + i.rest) - cool.length * 40;
    String intensity;

    switch (calm ? WorkoutFormat.flow : fmt) {
      case WorkoutFormat.flow:
        final types = kind == WorkoutKind.stretch ? {ExType.stretch} : {ExType.mobility, ExType.stretch, ExType.core};
        final n = (mainSec / 55).floor().clamp(5, 16);
        final list = <Exercise>[];
        for (var i = 0; i < n; i++) {
          final e = pick((e) => types.contains(e.type) && e.lvl <= math.max(2, target.round()));
          if (e == null) break;
          list.add(e);
        }
        final slots = list.fold(0, (a, e) => a + (e.uni ? 2 : 1));
        final rounds = slots == 0 ? 1 : (mainSec / (slots * 55)).round().clamp(1, 3);
        final work = slots == 0 ? 45 : ((mainSec / rounds / slots) - 10).round().clamp(30, 90);
        for (var rd = 1; rd <= rounds; rd++) {
          for (final e in list) {
            add(e, e.uni ? work * 2 : work, 10, Phase.main, round: rd, rounds: rounds);
          }
        }
        intensity = 'spokojnie, $work s na pozycję';

      case WorkoutFormat.tabata:
        // bloki po 4 min: 8 × (20 s pracy / 10 s przerwy), dwa ćwiczenia na zmianę
        final blocks = (mainSec / 300).round().clamp(1, 6);
        for (var b = 1; b <= blocks; b++) {
          final a = pickFor(groups[(b - 1) % groups.length], cardio: kind == WorkoutKind.hiit && b.isOdd) ??
              pick((e) => e.type == ExType.cardio);
          final c = pickFor(groups[b % groups.length], cardio: kind == WorkoutKind.hiit && b.isEven) ??
              pick((e) => e.type == ExType.strength);
          if (a == null || c == null) break;
          for (var i = 1; i <= 8; i++) {
            final e = i.isOdd ? a : c;
            final last = i == 8;
            // tabata to praca bez dzielenia na strony — przy ćwiczeniu jednostronnym strona zmienia się co interwał
            items.add(PlanItem(
              exId: e.id,
              work: 20,
              rest: last ? (b < blocks ? 60 : 15) : 10,
              phase: Phase.main,
              side: e.uni ? ((i + 1) ~/ 2).isOdd ? 1 : 2 : 0,
              round: i,
              rounds: 8,
              tag: 'Blok $b/$blocks',
            ));
          }
        }
        intensity = '$blocks × tabata (20/10)';

      case WorkoutFormat.sets:
      case WorkoutFormat.supersets:
        final sets = (profile.goal == Goal.strength ? 4 : 3) * (load < 0.95 ? 0.67 : 1.0);
        final nSets = sets.round().clamp(2, 5);
        final restSet = profile.goal == Goal.strength ? 75 : 60;
        final restEx = 90;
        int estimate(Exercise e, int? reps, int hold) =>
            reps != null ? math.max(15, (reps * e.anim.cycle).round()) : hold;
        (int?, int) dose(Exercise e) {
          if (e.isStatic) return (null, holdTarget(e, (30 + target * 5).round(), load: load));
          final reps = repsTarget(e, target, load: load);
          return (reps, estimate(e, reps, 0));
        }

        if (fmt == WorkoutFormat.sets) {
          int perEx(Exercise e) {
            final d = dose(e);
            return nSets * ((e.uni ? 2 : 1) * d.$2 + restSet) + restEx - restSet;
          }

          final list = <Exercise>[];
          var used0 = 0;
          for (var i = 0; i < 8; i++) {
            final e = pickFor(groups[i % groups.length]);
            if (e == null) break;
            final need = perEx(e);
            if (list.length >= 3 && used0 + need > mainSec) {
              used.remove(e.id);
              break;
            }
            list.add(e);
            used0 += need;
          }
          for (var i = 0; i < list.length; i++) {
            final e = list[i];
            final d = dose(e);
            for (var s = 1; s <= nSets; s++) {
              final lastSet = s == nSets;
              add(e, d.$2, lastSet ? (i < list.length - 1 ? restEx : 15) : restSet, Phase.main,
                  round: s, rounds: nSets, reps: d.$1, tag: 'Seria $s/$nSets');
            }
          }
          intensity = '${list.length} ćwiczeń × $nSets serie, przerwa $restSet s';
        } else {
          // superserie: pary ćwiczeń z różnych partii, A i B na zmianę
          final pairSec = (Exercise a, Exercise b) =>
              nSets * (dose(a).$2 * (a.uni ? 2 : 1) + 15 + dose(b).$2 * (b.uni ? 2 : 1) + restSet);
          final pairs = <(Exercise, Exercise)>[];
          var spent = 0;
          for (var i = 0; i < 4; i++) {
            final a = pickFor(groups[(2 * i) % groups.length]);
            final b = pickFor(groups[(2 * i + 1) % groups.length]);
            if (a == null || b == null) break;
            final need = pairSec(a, b);
            if (pairs.length >= 2 && spent + need > mainSec) break;
            pairs.add((a, b));
            spent += need;
          }
          for (var p = 0; p < pairs.length; p++) {
            final (a, b) = pairs[p];
            final da = dose(a), db = dose(b);
            final letter = String.fromCharCode(65 + p);
            for (var s = 1; s <= nSets; s++) {
              add(a, da.$2, 15, Phase.main, round: s, rounds: nSets, reps: da.$1, tag: '${letter}1 · seria $s/$nSets');
              final lastOfPair = s == nSets;
              add(b, db.$2, lastOfPair ? (p < pairs.length - 1 ? restEx : 15) : restSet, Phase.main,
                  round: s, rounds: nSets, reps: db.$1, tag: '${letter}2 · seria $s/$nSets');
            }
          }
          intensity = '${pairs.length} superserie × $nSets, przerwa $restSet s';
        }

      case WorkoutFormat.circuit:
      case WorkoutFormat.hiit:
      case WorkoutFormat.strengthIntervals:
        final lvl = target;
        int work, rest, roundRest, n;
        switch (fmt) {
          case WorkoutFormat.hiit:
            work = (25 + lvl * 3).round();
            rest = (32 - lvl * 4).round();
            roundRest = 45;
            n = 6;
          case WorkoutFormat.strengthIntervals:
            work = (45 + lvl * 3).round();
            rest = (40 - lvl * 2).round();
            roundRest = 60;
            n = 4;
          default:
            work = (28 + lvl * 4).round();
            rest = (32 - lvl * 3).round();
            roundRest = 60;
            n = kind == WorkoutKind.core ? 5 : 6;
        }
        if (r < 60) {
          work -= 5;
          rest += 10;
        } else if (r >= 80) {
          rest -= 3;
        }
        work = (work * load).round().clamp(20, 75);
        rest = (rest / load).round().clamp(10, 60);
        final hiitLike = fmt == WorkoutFormat.hiit || kind == WorkoutKind.hiit;
        final list = pickList(n, alternateCardio: hiitLike);
        if (fmt == WorkoutFormat.circuit && kind == WorkoutKind.fullBody && r >= 60 && list.length >= 5) {
          final c = pick((e) => e.type == ExType.cardio && e.lvl <= target.round() + 1);
          if (c != null) list[list.length - 1] = c;
        }
        int perRound() =>
            list.fold(0, (s, e) => s + (e.uni ? (math.max(15, work ~/ 2) * 2 + 5) : work) + rest) + roundRest;
        var rounds = (mainSec / perRound()).round();
        if (rounds < 1) {
          rounds = 1;
          while (list.length > 3 && perRound() > mainSec) {
            used.remove(list.removeLast().id);
          }
        }
        rounds = rounds.clamp(1, 6);
        final planned = rounds * perRound() - roundRest;
        final workSlots = rounds * list.length;
        if (workSlots > 0) {
          final delta = ((mainSec - planned) / workSlots).round();
          work = (work + delta).clamp(20, 75);
        }
        for (var rd = 1; rd <= rounds; rd++) {
          for (var i = 0; i < list.length; i++) {
            final lastInRound = i == list.length - 1;
            add(list[i], work, lastInRound && rd < rounds ? roundRest : rest, Phase.main, round: rd, rounds: rounds);
          }
        }
        if (items.isNotEmpty) items.last.rest = 15;
        intensity = '$work s pracy / $rest s przerwy';
    }

    for (final e in cool) {
      add(e, 40, 0, Phase.cooldown);
    }

    final lacking = groups.where((g) => muscleGroups.contains(g) && (week[g] ?? 0) < weeklySetTarget ~/ 2).toList();
    final reasons = <String>[
      if (reason != null) reason,
      _readinessLine(readiness),
      if (repsMode) 'Cele powtórzeń wynikają z Twoich ostatnich serii — zrobione wszystkie, więc idziemy wyżej.',
      if (!calm && lacking.isNotEmpty && sessions.isNotEmpty)
        'W tym tygodniu najmniej serii: ${lacking.take(2).join(', ')} — od nich zaczynamy.',
      if (load < 0.95) 'Tydzień lżejszy w planie — mniej serii, żeby organizm nadrobił regenerację.',
      if (profile.limits.isNotEmpty) 'Pomijam ćwiczenia obciążające: ${profile.limits.join(', ')}.',
      if (_jumpsOff && !profile.limits.contains('kolana')) 'Bez skoków — cicho dla sąsiadów.',
    ];
    return WorkoutPlan(
      kind: kind,
      format: calm ? WorkoutFormat.flow : fmt,
      title: calm ? kindLabel[kind]! : '${kindLabel[kind]} · ${formatLabel[fmt]}',
      items: items,
      readiness: readiness.score,
      intensity: intensity,
      reasons: reasons,
      programDay: programDay,
    );
  }

  // ---------------------------------------------------------------- plan wielotygodniowy

  static const _templates = <Goal, List<(WorkoutKind, WorkoutFormat)>>{
    Goal.strength: [
      (WorkoutKind.upper, WorkoutFormat.sets),
      (WorkoutKind.lower, WorkoutFormat.sets),
      (WorkoutKind.back, WorkoutFormat.supersets),
      (WorkoutKind.fullBody, WorkoutFormat.strengthIntervals),
      (WorkoutKind.arms, WorkoutFormat.supersets),
      (WorkoutKind.core, WorkoutFormat.circuit),
      (WorkoutKind.mobility, WorkoutFormat.flow),
    ],
    Goal.burn: [
      (WorkoutKind.hiit, WorkoutFormat.tabata),
      (WorkoutKind.lower, WorkoutFormat.circuit),
      (WorkoutKind.upper, WorkoutFormat.hiit),
      (WorkoutKind.core, WorkoutFormat.tabata),
      (WorkoutKind.fullBody, WorkoutFormat.strengthIntervals),
      (WorkoutKind.mobility, WorkoutFormat.flow),
      (WorkoutKind.stretch, WorkoutFormat.flow),
    ],
    Goal.fitness: [
      (WorkoutKind.hiit, WorkoutFormat.hiit),
      (WorkoutKind.fullBody, WorkoutFormat.circuit),
      (WorkoutKind.core, WorkoutFormat.tabata),
      (WorkoutKind.lower, WorkoutFormat.strengthIntervals),
      (WorkoutKind.upper, WorkoutFormat.circuit),
      (WorkoutKind.mobility, WorkoutFormat.flow),
      (WorkoutKind.stretch, WorkoutFormat.flow),
    ],
    Goal.general: [
      (WorkoutKind.fullBody, WorkoutFormat.circuit),
      (WorkoutKind.upper, WorkoutFormat.strengthIntervals),
      (WorkoutKind.lower, WorkoutFormat.sets),
      (WorkoutKind.core, WorkoutFormat.tabata),
      (WorkoutKind.back, WorkoutFormat.supersets),
      (WorkoutKind.mobility, WorkoutFormat.flow),
      (WorkoutKind.stretch, WorkoutFormat.flow),
    ],
    Goal.mobility: [
      (WorkoutKind.mobility, WorkoutFormat.flow),
      (WorkoutKind.core, WorkoutFormat.circuit),
      (WorkoutKind.stretch, WorkoutFormat.flow),
      (WorkoutKind.fullBody, WorkoutFormat.strengthIntervals),
      (WorkoutKind.back, WorkoutFormat.circuit),
      (WorkoutKind.mobility, WorkoutFormat.flow),
      (WorkoutKind.stretch, WorkoutFormat.flow),
    ],
  };

  /// Dwa dni w tygodniu = dwa treningi całego ciała, żeby każda partia dostała bodziec.
  static List<(WorkoutKind, WorkoutFormat)> weekTemplate(Goal goal, int days) {
    final t = _templates[goal]!;
    if (days <= 2) {
      final f = goal == Goal.strength ? WorkoutFormat.sets : (goal == Goal.mobility ? WorkoutFormat.flow : WorkoutFormat.circuit);
      return [
        (goal == Goal.mobility ? WorkoutKind.mobility : WorkoutKind.fullBody, f),
        (WorkoutKind.fullBody, goal == Goal.strength ? WorkoutFormat.supersets : WorkoutFormat.strengthIntervals),
      ].take(days).toList();
    }
    return t.take(days).toList();
  }

  /// Mnożnik objętości: 3 tygodnie wzrostu, 4. lżejszy.
  static double weekLoad(int week) => week % 4 == 0 ? 0.75 : 1 + 0.06 * ((week - 1) % 4);

  Program buildProgram({required int weeks, required List<int> weekdays, required int minutes, DateTime? start}) {
    final from = DateTime((start ?? now).year, (start ?? now).month, (start ?? now).day);
    final wd = [...weekdays]..sort();
    final tpl = weekTemplate(profile.goal, wd.length);
    final days = <ProgramDay>[];
    // pierwszy tydzień liczymy od poniedziałku tygodnia startu; dni przed startem przesuwamy na kolejne wolne
    var monday = from.subtract(Duration(days: from.weekday - 1));
    for (var w = 1; w <= weeks; w++) {
      for (var i = 0; i < wd.length; i++) {
        var date = monday.add(Duration(days: wd[i] - 1));
        if (date.isBefore(from)) date = from.add(Duration(days: i));
        final (k, f) = tpl[i % tpl.length];
        days.add(ProgramDay(
          id: 'w${w}d${i + 1}',
          week: w,
          index: i + 1,
          date: date,
          kind: k,
          format: f,
          minutes: f == WorkoutFormat.flow ? math.max(15, (minutes * 0.7).round()) : minutes,
          load: weekLoad(w),
        ));
      }
      monday = monday.add(const Duration(days: 7));
    }
    return Program(
      id: 'p${now.millisecondsSinceEpoch}',
      name: '${goalLabel[profile.goal]} · $weeks tyg.',
      goal: profile.goal,
      start: from,
      weeks: weeks,
      weekdays: wd,
      days: days,
    );
  }

  String _readinessLine(Readiness r) {
    if (!r.hasData) {
      return 'Nie mam jeszcze danych o śnie i tętnie — oceń samopoczucie albo zmierz HRV, a dopasuję trening lepiej.';
    }
    final worst = [...r.factors]..sort((a, b) => a.effect.compareTo(b.effect));
    final neg = worst.where((f) => f.effect <= -5).take(2).map((f) => '${f.label.toLowerCase()} ${f.value}');
    if (r.score < 40) return 'Gotowość ${r.score}/100 (${neg.join(', ')}) — dziś tylko lekki ruch.';
    if (r.score < 60) return 'Gotowość ${r.score}/100${neg.isEmpty ? '' : ' (${neg.join(', ')})'} — krótsza praca, dłuższe przerwy.';
    if (r.score >= 80) return 'Gotowość ${r.score}/100 — dobry dzień, żeby docisnąć.';
    return 'Gotowość ${r.score}/100 — trening według planu.';
  }

  /// Zamiennik ćwiczenia z tej samej grupy i typu.
  Exercise? alternative(Exercise current, Set<String> inPlan, {int seed = 0}) {
    final rnd = math.Random(seed);
    final c = library.where((e) {
      if (e.id == current.id || inPlan.contains(e.id) || hidden.contains(e.id)) return false;
      if (!e.availableWith(profile.equipment) || e.stress.any(profile.limits.contains)) return false;
      if (e.impact && _jumpsOff) return false;
      final sameType = e.type == current.type ||
          ({ExType.strength, ExType.core}.contains(e.type) && {ExType.strength, ExType.core}.contains(current.type));
      return sameType && e.groups.any(current.groups.contains);
    }).toList();
    if (c.isEmpty) return null;
    c.sort((a, b) => (a.lvl - current.lvl).abs().compareTo((b.lvl - current.lvl).abs()));
    final top = c.take(4).toList();
    return top[rnd.nextInt(top.length)];
  }

  // ---------------------------------------------------------------- po treningu

  /// Nowy poziom po treningu: cel to RPE ok. 7 przy pełnym wykonaniu.
  double nextLevel(Session s) {
    var l = profile.level;
    if (s.kind == WorkoutKind.mobility || s.kind == WorkoutKind.stretch) return l;
    final c = s.completion;
    if (c < 0.6) {
      l -= 0.15;
    } else {
      l += (7 - s.rpe) * 0.08 * c;
    }
    final easy = s.feedback.values.where((v) => v < 0).length;
    final hard = s.feedback.values.where((v) => v > 0).length;
    l += (easy - hard) * 0.03;
    return (l.clamp(1.0, 5.0) * 100).round() / 100;
  }

  // ---------------------------------------------------------------- tętno i kalorie

  /// Strefa 1–5 dla tętna (procent tętna maksymalnego).
  static int zone(int bpm, int maxHr) {
    final p = bpm / maxHr;
    if (p < 0.6) return 1;
    if (p < 0.7) return 2;
    if (p < 0.8) return 3;
    if (p < 0.9) return 4;
    return 5;
  }

  /// Kalorie: z tętna (wzór Keytel), a bez opaski z MET ćwiczeń.
  static double kcal({
    required Profile p,
    required int seconds,
    int? avgHr,
    double metSeconds = 0,
  }) {
    final w = p.weightKg, a = p.age.toDouble();
    if (avgHr != null && avgHr > 60) {
      final perMin = p.sex == 'k'
          ? (-20.4022 + 0.4472 * avgHr - 0.1263 * w + 0.074 * a) / 4.184
          : (-55.0969 + 0.6309 * avgHr + 0.1988 * w + 0.2017 * a) / 4.184;
      return math.max(0, perMin * seconds / 60);
    }
    // MET × 3,5 × kg / 200 = kcal/min
    return metSeconds / 60 * 3.5 * w / 200;
  }

  static double _median(List<double> v) {
    final s = [...v]..sort();
    final m = s.length ~/ 2;
    return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
  }

  static String _hm(double h) {
    final m = (h * 60).round();
    return '${m ~/ 60} h ${(m % 60).toString().padLeft(2, '0')} min';
  }

  /// RMSSD z odstępów RR (ms), z odrzuceniem artefaktów.
  static double? rmssd(List<double> rr) {
    final clean = <double>[];
    for (final v in rr) {
      if (v < 300 || v > 2000) continue;
      if (clean.isNotEmpty && (v - clean.last).abs() > clean.last * 0.25) continue;
      clean.add(v);
    }
    if (clean.length < 20) return null;
    var sum = 0.0;
    for (var i = 1; i < clean.length; i++) {
      final d = clean[i] - clean[i - 1];
      sum += d * d;
    }
    return math.sqrt(sum / (clean.length - 1));
  }
}
