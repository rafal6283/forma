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
    WorkoutKind.core: ['brzuch', 'plecy'],
    WorkoutKind.hiit: ['całe ciało', 'nogi', 'brzuch'],
    WorkoutKind.mobility: ['plecy', 'nogi', 'barki'],
    WorkoutKind.stretch: ['nogi', 'plecy'],
  };

  static const _goalRotation = {
    Goal.general: [WorkoutKind.fullBody, WorkoutKind.upper, WorkoutKind.lower, WorkoutKind.core, WorkoutKind.hiit],
    Goal.strength: [WorkoutKind.upper, WorkoutKind.lower, WorkoutKind.fullBody, WorkoutKind.core],
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

  // ---------------------------------------------------------------- generator

  WorkoutPlan generate({
    required WorkoutKind kind,
    required Readiness readiness,
    int? minutes,
    int seed = 0,
    String? reason,
  }) {
    final rnd = math.Random(seed == 0 ? now.millisecondsSinceEpoch : seed);
    final total = (minutes ?? profile.minutes) * 60;
    final r = readiness.score;
    final adj = r < 40 ? -1.5 : r < 60 ? -0.7 : r >= 80 ? 0.3 : 0.0;
    final target = (profile.level + adj).clamp(1.0, 5.0);
    final calm = kind == WorkoutKind.mobility || kind == WorkoutKind.stretch;

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
      // trudniejsze niż poziom karzemy mocniej niż łatwiejsze
      if (e.lvl > target + 1) s -= 2;
      final fb = exScore[e.id] ?? 0;
      if (fb > 0 && e.lvl >= target) s -= fb * 0.8; // oceniane jako za trudne
      if (fb < 0 && e.lvl <= target) s += fb * 0.6; // za łatwe
      final last = exLast[e.id];
      if (last != null && now.difference(last).inHours < 48) s -= 1.2; // różnorodność
      if (favorites.contains(e.id)) s += 1;
      if (e.needsEquipment) s += 0.8; // skoro jest sprzęt, korzystajmy
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
    void add(Exercise e, int work, int rest, Phase p, {int round = 1, int rounds = 1}) {
      if (e.uni) {
        final half = math.max(15, work ~/ 2 + (e.isStatic ? 5 : 0));
        items.add(PlanItem(exId: e.id, work: half, rest: 5, phase: p, side: 1, round: round, rounds: rounds));
        items.add(PlanItem(exId: e.id, work: half, rest: rest, phase: p, side: 2, round: round, rounds: rounds));
      } else {
        items.add(PlanItem(exId: e.id, work: work, rest: rest, phase: p, round: round, rounds: rounds));
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
      // od spokojnych do żywszych
      warm.sort((a, b) => a.met.compareTo(b.met));
      for (final e in warm) {
        add(e, 30, 0, Phase.warmup);
      }
    }

    // --- wyciszenie
    final coolSec = calm ? 0 : math.max(120, (total * 0.10).round());
    final cool = <Exercise>[];
    if (coolSec > 0) {
      final groups = _kindGroups[kind]!;
      final n = (coolSec / 40).round().clamp(3, 5);
      for (var i = 0; i < n; i++) {
        final g = groups[i % groups.length];
        final e = pick((e) => e.type == ExType.stretch && (e.groups.contains(g) || i >= groups.length)) ??
            pick((e) => e.type == ExType.stretch);
        if (e != null) cool.add(e);
      }
    }

    // --- część główna
    final mainSec = total - items.fold(0, (s, i) => s + i.work + i.rest) - cool.length * 40;
    String intensity;
    if (calm) {
      final types = kind == WorkoutKind.stretch ? {ExType.stretch} : {ExType.mobility, ExType.stretch, ExType.core};
      final work = 45;
      final n = (mainSec / (work + 10)).floor().clamp(5, 16);
      final list = <Exercise>[];
      for (var i = 0; i < n; i++) {
        final e = pick((e) => types.contains(e.type) && e.lvl <= math.max(2, target.round()));
        if (e == null) break;
        list.add(e);
      }
      // mało ćwiczeń? druga runda
      final rounds = list.length * (work + 10) * 2 <= mainSec ? 2 : 1;
      for (var rd = 1; rd <= rounds; rd++) {
        for (final e in list) {
          add(e, work, 10, Phase.main, round: rd, rounds: rounds);
        }
      }
      intensity = 'spokojnie';
    } else {
      final lvl = target;
      var work = kind == WorkoutKind.hiit ? (25 + lvl * 3).round() : (28 + lvl * 4).round();
      var rest = kind == WorkoutKind.hiit ? (32 - lvl * 4).round() : (32 - lvl * 3).round();
      if (r < 60) {
        work -= 5;
        rest += 10;
      } else if (r >= 80) {
        rest -= 3;
      }
      work = work.clamp(20, 50);
      rest = rest.clamp(10, 45);
      final roundRest = kind == WorkoutKind.hiit ? 45 : 60;

      final n = kind == WorkoutKind.hiit ? 5 : (kind == WorkoutKind.core ? 5 : 6);
      final groups = _kindGroups[kind]!;
      final list = <Exercise>[];
      for (var i = 0; i < n; i++) {
        Exercise? e;
        if (kind == WorkoutKind.hiit) {
          e = i.isEven
              ? pick((e) => e.type == ExType.cardio)
              : pick((e) => e.type == ExType.strength || e.type == ExType.core);
        } else if (kind == WorkoutKind.core) {
          e = pick((e) => e.type == ExType.core || (e.type == ExType.strength && e.groups.contains('brzuch')));
          e ??= pick((e) => e.groups.contains('plecy') && e.type == ExType.strength);
        } else {
          final g = groups[i % groups.length];
          e = pick((e) => (e.type == ExType.strength || e.type == ExType.core) && e.groups.contains(g));
          e ??= pick((e) => e.type == ExType.strength && e.groups.any(groups.contains));
        }
        e ??= pick((e) => e.type == ExType.strength || e.type == ExType.core || e.type == ExType.cardio);
        if (e != null) list.add(e);
      }
      if (kind == WorkoutKind.fullBody && r >= 60 && list.length >= 5) {
        // na koniec obwodu coś dynamicznego
        final c = pick((e) => e.type == ExType.cardio && e.lvl <= target.round() + 1);
        if (c != null) list[list.length - 1] = c;
      }
      int perRound() =>
          list.fold(0, (s, e) => s + (e.uni ? (math.max(15, work ~/ 2) * 2 + 5) : work) + rest) + roundRest;
      var rounds = (mainSec / perRound()).floor();
      if (rounds < 1) {
        rounds = 1;
        while (list.length > 3 && perRound() > mainSec) {
          used.remove(list.removeLast().id);
        }
      }
      rounds = rounds.clamp(1, 6);
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

    final reasons = <String>[
      if (reason != null) reason,
      _readinessLine(readiness),
      if (profile.limits.isNotEmpty) 'Pomijam ćwiczenia obciążające: ${profile.limits.join(', ')}.',
      if (_jumpsOff && !profile.limits.contains('kolana')) 'Bez skoków — cicho dla sąsiadów.',
    ];
    return WorkoutPlan(
      kind: kind,
      title: kindLabel[kind]!,
      items: items,
      readiness: readiness.score,
      intensity: intensity,
      reasons: reasons,
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
