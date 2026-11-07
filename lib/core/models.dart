import 'dart:convert';

import 'figure.dart';

enum ExType { warmup, cardio, strength, core, mobility, stretch }

ExType exTypeOf(String s) => ExType.values.firstWhere((e) => e.name == s, orElse: () => ExType.strength);

const exTypeLabel = {
  ExType.warmup: 'Rozgrzewka',
  ExType.cardio: 'Kardio',
  ExType.strength: 'Siła',
  ExType.core: 'Brzuch',
  ExType.mobility: 'Mobilność',
  ExType.stretch: 'Rozciąganie',
};

/// Sprzęt, który można zaznaczyć w ustawieniach.
const equipmentLabel = {
  'chair': 'Krzesło lub ławka',
  'db': 'Hantle',
  'kb': 'Kettlebell',
  'band': 'Guma oporowa',
  'bar': 'Drążek',
  'wheel': 'Kółko do brzucha',
};

/// Ograniczenia: ćwiczenia obciążające te miejsca są pomijane.
const limitLabels = ['kolana', 'plecy', 'nadgarstki', 'barki', 'łokcie', 'kostki', 'biodra', 'szyja'];

/// Czego unika trener przy danej dolegliwości (opis dla użytkownika).
const limitHints = {
  'kolana': 'bez skoków, głębokich przysiadów i wykroków',
  'plecy': 'bez skłonów z obciążeniem, unoszenia nóg w leżeniu i skrętów',
  'nadgarstki': 'bez podporu na dłoniach — deski i pompki na przedramionach lub pięściach',
  'barki': 'bez wyciskania nad głowę, pompek w pike i pompek na poręczach',
  'łokcie': 'bez prostowania ramion z obciążeniem, pompek diamentowych i podciągania',
  'kostki': 'bez skoków, wspięć na palce i biegu w miejscu',
  'biodra': 'bez wykroków, szerokich przysiadów i głębokiego rozciągania bioder',
  'szyja': 'bez brzuszków z dłońmi za głową i pozycji z ciężarem na karku',
};

const muscleGroups = ['nogi', 'pośladki', 'klatka', 'plecy', 'barki', 'ramiona', 'brzuch'];

/// Mięśnie na mapie (przód/tył) — klucze z assets/exercises.json i assets/muscles.json.
const muscleLabel = {
  'chest': 'Klatka piersiowa',
  'shoulders': 'Barki',
  'biceps': 'Biceps',
  'triceps': 'Triceps',
  'forearms': 'Przedramiona',
  'abs': 'Brzuch',
  'obliques': 'Mięśnie skośne',
  'traps': 'Kaptury',
  'upper_back': 'Górna część pleców',
  'lats': 'Najszersze grzbietu',
  'lower_back': 'Lędźwie',
  'glutes': 'Pośladki',
  'abductors': 'Boczna część bioder',
  'adductors': 'Przywodziciele',
  'quads': 'Przód uda',
  'hamstrings': 'Tył uda',
  'calves': 'Łydki',
};

class Exercise {
  final String id, name;
  final ExType type;
  final List<String> groups, eq, stress, tips;
  final List<String> aka; // nazwy tego ruchu w Fitify
  final int lvl;
  final double met;
  final bool impact, uni, isStatic;
  final String? hold, easier, harder;
  final FigAnim anim;
  final Map<String, double> muscles; // 1 = główny, 0,5 = pomocniczy
  final String strava; // exercise_type Stravy (serie → mapa mięśni)
  final int fitCategory; // exercise_category w pliku FIT
  final int? fitSubtype; // podtyp w kategorii (gdy jest odpowiednik)

  Exercise({
    required this.id,
    required this.name,
    required this.type,
    required this.groups,
    required this.eq,
    required this.stress,
    required this.tips,
    this.aka = const [],
    required this.lvl,
    required this.met,
    required this.impact,
    required this.uni,
    required this.isStatic,
    required this.anim,
    this.muscles = const {},
    this.strava = 'TOTAL_BODY_GENERIC',
    this.fitCategory = 29,
    this.fitSubtype,
    this.hold,
    this.easier,
    this.harder,
  });

  factory Exercise.fromJson(Map<String, dynamic> j, Map<String, Pose> lib) {
    List<String> s(String k) => ((j[k] as List?) ?? const []).cast<String>();
    return Exercise(
      id: j['id'] as String,
      name: j['name'] as String,
      type: exTypeOf(j['type'] as String),
      groups: s('groups'),
      eq: s('eq'),
      stress: s('stress'),
      tips: s('tips'),
      aka: s('aka'),
      lvl: (j['lvl'] as num).toInt(),
      met: (j['met'] as num).toDouble(),
      impact: j['impact'] == true,
      uni: j['uni'] == true,
      isStatic: j['static'] == true,
      hold: j['hold'] as String?,
      easier: j['easier'] as String?,
      harder: j['harder'] as String?,
      anim: FigAnim.fromJson((j['anim'] as Map).cast<String, dynamic>(), lib),
      muscles: ((j['m'] as Map?) ?? const {}).map((k, v) => MapEntry(k as String, (v as num).toDouble())),
      strava: j['sv'] as String? ?? 'TOTAL_BODY_GENERIC',
      fitCategory: ((j['fc'] as List?)?.first as num?)?.toInt() ?? 29,
      fitSubtype: (j['fc'] as List?) != null && (j['fc'] as List).length > 1 ? ((j['fc'] as List)[1] as num).toInt() : null,
    );
  }

  /// Każda pozycja sprzętu musi być dostępna; „db|kb” = wystarczy jedno z nich.
  bool availableWith(Set<String> owned) => eq.every((e) => e.split('|').any(owned.contains));

  bool get needsEquipment => eq.isNotEmpty;

  /// Ćwiczenie z ciężarem (hantle / kettlebell) — zapisujemy kilogramy i podpowiadamy ciężar.
  bool get weighted => hold == 'db' || hold == 'db1' || hold == 'kb';

  /// Ile mniej więcej powtórzeń w [seconds] (dla podpowiedzi przy ćwiczeniach dynamicznych).
  int? repsFor(int seconds) {
    if (isStatic || type == ExType.stretch) return null;
    final per = anim.cycle * (uni ? 1 : 1);
    final r = (seconds / per).round();
    return r < 2 ? null : r;
  }
}

enum Goal { general, strength, burn, fitness, mobility }

const goalLabel = {
  Goal.general: 'Ogólna forma',
  Goal.strength: 'Siła i mięśnie',
  Goal.burn: 'Spalanie tłuszczu',
  Goal.fitness: 'Kondycja',
  Goal.mobility: 'Mobilność i zdrowe plecy',
};

enum WorkoutKind { fullBody, upper, lower, back, arms, core, hiit, mobility, stretch }

const kindLabel = {
  WorkoutKind.fullBody: 'Całe ciało',
  WorkoutKind.upper: 'Góra ciała',
  WorkoutKind.lower: 'Nogi i pośladki',
  WorkoutKind.back: 'Plecy i barki',
  WorkoutKind.arms: 'Ramiona i barki',
  WorkoutKind.core: 'Brzuch i core',
  WorkoutKind.hiit: 'Interwały HIIT',
  WorkoutKind.mobility: 'Mobilność',
  WorkoutKind.stretch: 'Rozciąganie',
};

/// Format treningu (jak w Fitify): niezależny od partii ciała.
enum WorkoutFormat { circuit, hiit, tabata, strengthIntervals, sets, supersets, dropSets, flow }

const formatLabel = {
  WorkoutFormat.circuit: 'Obwód',
  WorkoutFormat.hiit: 'HIIT',
  WorkoutFormat.tabata: 'Tabata',
  WorkoutFormat.strengthIntervals: 'Interwały siłowe',
  WorkoutFormat.sets: 'Serie siłowe',
  WorkoutFormat.supersets: 'Superserie',
  WorkoutFormat.dropSets: 'Drop-sety',
  WorkoutFormat.flow: 'Spokojny przepływ',
};

const formatHint = {
  WorkoutFormat.circuit: 'Ćwiczenia jedno po drugim, kilka rund',
  WorkoutFormat.hiit: 'Krótka, mocna praca i krótkie przerwy',
  WorkoutFormat.tabata: 'Bloki 8 × (20 s pracy / 10 s przerwy)',
  WorkoutFormat.strengthIntervals: 'Długa praca siłowa, mniej ćwiczeń',
  WorkoutFormat.sets: 'Serie na powtórzenia z przerwą — klasyczna siłownia',
  WorkoutFormat.supersets: 'Pary ćwiczeń A/B na przemian',
  WorkoutFormat.dropSets: 'Seria do zmęczenia, potem lżej (mniejszy ciężar albo łatwiejsza wersja) bez przerwy',
  WorkoutFormat.flow: 'Mobilność i rozciąganie w swoim tempie',
};

WorkoutFormat formatOf(String? s) =>
    WorkoutFormat.values.firstWhere((e) => e.name == s, orElse: () => WorkoutFormat.circuit);

WorkoutKind kindOf(String s) =>
    WorkoutKind.values.firstWhere((e) => e.name == s, orElse: () => WorkoutKind.fullBody);

class Profile {
  String name;
  String sex; // 'm' / 'k'
  int birthYear;
  double weightKg;
  int heightCm;
  double level; // 1..5, dostosowywany po treningach
  Goal goal;
  Set<String> equipment;
  Set<String> limits;
  bool noJumping;
  int minutes;
  int daysPerWeek;
  bool voice;
  bool beeps;
  bool healthConnect;
  String? hrDeviceId;
  String? hrDeviceName;
  int? maxHrOverride;
  bool onboarded;
  bool hrControl; // przerwy i podpowiedzi wg tętna, pomiar regeneracji
  bool voiceControl; // komendy głosowe w trakcie treningu
  bool stravaAuto; // wysyłaj po treningu
  bool stravaMatch; // uzupełnij aktywność z zegarka zamiast tworzyć nową
  bool stravaSets; // trening siłowy jako nowa aktywność z seriami (mapa mięśni w Stravie)
  bool reminders; // przypomnienie o treningu (i o zagrożonej serii)
  int reminderHour;
  bool warmup; // rozgrzewka dobrana do partii
  bool cooldown; // rozciąganie na koniec
  Map<String, DateTime> limitUntil; // dolegliwości czasowe: do kiedy oszczędzać (brak wpisu = na stałe)

  Profile({
    this.name = '',
    this.sex = 'm',
    this.birthYear = 1985,
    this.weightKg = 80,
    this.heightCm = 178,
    this.level = 2,
    this.goal = Goal.general,
    Set<String>? equipment,
    Set<String>? limits,
    this.noJumping = false,
    this.minutes = 25,
    this.daysPerWeek = 3,
    this.voice = true,
    this.beeps = true,
    this.healthConnect = false,
    this.hrDeviceId,
    this.hrDeviceName,
    this.maxHrOverride,
    this.onboarded = false,
    this.hrControl = true,
    this.voiceControl = false,
    this.stravaAuto = true,
    this.stravaMatch = true,
    this.stravaSets = true,
    this.warmup = true,
    this.cooldown = true,
    this.reminders = false,
    this.reminderHour = 18,
    Map<String, DateTime>? limitUntil,
  })  : equipment = equipment ?? {'chair'},
        limits = limits ?? {},
        limitUntil = limitUntil ?? {};

  /// Dolegliwości obowiązujące dziś (czasowe po terminie przestają działać).
  Set<String> get activeLimits {
    final now = DateTime.now();
    return {for (final l in limits) if (limitUntil[l] == null || limitUntil[l]!.isAfter(now)) l};
  }

  int get age => DateTime.now().year - birthYear;
  int get maxHr => maxHrOverride ?? (208 - 0.7 * age).round();

  Map<String, dynamic> toJson() => {
        'name': name,
        'sex': sex,
        'birthYear': birthYear,
        'weightKg': weightKg,
        'heightCm': heightCm,
        'level': level,
        'goal': goal.name,
        'equipment': equipment.toList(),
        'limits': limits.toList(),
        'noJumping': noJumping,
        'minutes': minutes,
        'daysPerWeek': daysPerWeek,
        'voice': voice,
        'beeps': beeps,
        'healthConnect': healthConnect,
        'hrDeviceId': hrDeviceId,
        'hrDeviceName': hrDeviceName,
        'maxHrOverride': maxHrOverride,
        'onboarded': onboarded,
        'hrControl': hrControl,
        'voiceControl': voiceControl,
        'stravaAuto': stravaAuto,
        'stravaMatch': stravaMatch,
        'stravaSets': stravaSets,
        'warmup': warmup,
        'reminders': reminders,
        'reminderHour': reminderHour,
        'cooldown': cooldown,
        'limitUntil': limitUntil.map((k, v) => MapEntry(k, v.toIso8601String())),
      };

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        name: j['name'] as String? ?? '',
        sex: j['sex'] as String? ?? 'm',
        birthYear: (j['birthYear'] as num?)?.toInt() ?? 1985,
        weightKg: (j['weightKg'] as num?)?.toDouble() ?? 80,
        heightCm: (j['heightCm'] as num?)?.toInt() ?? 178,
        level: (j['level'] as num?)?.toDouble() ?? 2,
        goal: Goal.values.firstWhere((g) => g.name == j['goal'], orElse: () => Goal.general),
        equipment: ((j['equipment'] as List?) ?? const ['chair']).cast<String>().toSet(),
        limits: ((j['limits'] as List?) ?? const []).cast<String>().toSet(),
        noJumping: j['noJumping'] == true,
        minutes: (j['minutes'] as num?)?.toInt() ?? 25,
        daysPerWeek: (j['daysPerWeek'] as num?)?.toInt() ?? 3,
        voice: j['voice'] != false,
        beeps: j['beeps'] != false,
        healthConnect: j['healthConnect'] == true,
        hrDeviceId: j['hrDeviceId'] as String?,
        hrDeviceName: j['hrDeviceName'] as String?,
        maxHrOverride: (j['maxHrOverride'] as num?)?.toInt(),
        onboarded: j['onboarded'] == true,
        hrControl: j['hrControl'] != false,
        voiceControl: j['voiceControl'] == true,
        stravaAuto: j['stravaAuto'] != false,
        stravaMatch: j['stravaMatch'] != false,
        stravaSets: j['stravaSets'] != false,
        warmup: j['warmup'] != false,
        reminders: j['reminders'] == true,
        reminderHour: (j['reminderHour'] as num?)?.toInt() ?? 18,
        cooldown: j['cooldown'] != false,
        limitUntil: {
          for (final e in ((j['limitUntil'] as Map?) ?? const {}).entries)
            if (DateTime.tryParse('${e.value}') != null) '${e.key}': DateTime.parse('${e.value}'),
        },
      );
}

enum Phase { warmup, main, cooldown }

const phaseLabel = {Phase.warmup: 'Rozgrzewka', Phase.main: 'Trening', Phase.cooldown: 'Wyciszenie'};

/// Jedna pozycja planu: ćwiczenie przez [work] s, potem [rest] s przerwy.
class PlanItem {
  String exId;
  int work;
  int rest;
  Phase phase;
  int side; // 0 = obie / nie dotyczy, 1 = prawa, 2 = lewa
  int round;
  int rounds;
  int? reps; // serie na powtórzenia (null = na czas)
  String? tag; // np. „A1”, „B2” w superseriach, „Blok 1” w tabacie

  PlanItem({
    required this.exId,
    required this.work,
    required this.rest,
    required this.phase,
    this.side = 0,
    this.round = 1,
    this.rounds = 1,
    this.reps,
    this.tag,
  });

  Map<String, dynamic> toJson() => {
        'ex': exId,
        'w': work,
        'r': rest,
        'p': phase.name,
        's': side,
        'rd': round,
        'rds': rounds,
        if (reps != null) 'reps': reps,
        if (tag != null) 'tag': tag,
      };

  factory PlanItem.fromJson(Map<String, dynamic> j) => PlanItem(
        exId: j['ex'] as String,
        work: (j['w'] as num).toInt(),
        rest: (j['r'] as num).toInt(),
        phase: Phase.values.firstWhere((p) => p.name == j['p'], orElse: () => Phase.main),
        side: (j['s'] as num?)?.toInt() ?? 0,
        round: (j['rd'] as num?)?.toInt() ?? 1,
        rounds: (j['rds'] as num?)?.toInt() ?? 1,
        reps: (j['reps'] as num?)?.toInt(),
        tag: j['tag'] as String?,
      );
}

class WorkoutPlan {
  WorkoutKind kind;
  WorkoutFormat format;
  String title;
  List<PlanItem> items;
  int readiness;
  String intensity;
  List<String> reasons;
  String? programDay; // dzień planu, który ten trening realizuje
  String? challenge; // dzień wyzwania

  WorkoutPlan({
    required this.kind,
    this.format = WorkoutFormat.circuit,
    required this.title,
    required this.items,
    required this.readiness,
    required this.intensity,
    required this.reasons,
    this.programDay,
    this.challenge,
  });

  int get seconds => items.fold(0, (s, i) => s + i.work + i.rest);
  int get minutes => (seconds / 60).round();
}

/// Wykonane ćwiczenie w sesji.
class DoneItem {
  final String exId;
  final int seconds;
  final int side;
  final int? reps; // wykonane powtórzenia (serie na powtórzenia)
  final int? target; // cel powtórzeń
  final double? weight; // ciężar (kg) przy hantlach / kettlebell
  DoneItem(this.exId, this.seconds, this.side, {this.reps, this.target, this.weight});
  Map<String, dynamic> toJson() => {
        'ex': exId,
        's': seconds,
        'sd': side,
        if (reps != null) 'r': reps,
        if (target != null) 't': target,
        if (weight != null) 'w': weight,
      };
  factory DoneItem.fromJson(Map<String, dynamic> j) => DoneItem(
        j['ex'] as String,
        (j['s'] as num).toInt(),
        (j['sd'] as num?)?.toInt() ?? 0,
        reps: (j['r'] as num?)?.toInt(),
        target: (j['t'] as num?)?.toInt(),
        weight: (j['w'] as num?)?.toDouble(),
      );
}

class Session {
  final String id;
  final DateTime start, end;
  final WorkoutKind kind;
  final String title;
  final List<DoneItem> done;
  final double kcal;
  final int? avgHr, maxHr;
  final List<int> hr; // średnie tętno co 5 s (0 = brak odczytu)
  final List<int> zones; // sekundy w strefach 1–5
  int rpe; // 1–10
  final WorkoutFormat format;
  final String? programDay;
  final String? challenge; // „plank30:7” = wyzwanie, dzień
  final int? hrr; // spadek tętna w minutę po treningu
  int? stravaId; // aktywność w Stravie (uzupełniona lub wysłana)
  bool stravaPending; // czeka na aktywność z zegarka
  final int readiness;
  final int plannedSeconds;
  Map<String, int> feedback; // ćwiczenie → -1 za łatwe, 1 za trudne
  bool inHealth;

  Session({
    required this.id,
    required this.start,
    required this.end,
    required this.kind,
    required this.title,
    required this.done,
    required this.kcal,
    this.avgHr,
    this.maxHr,
    this.hr = const [],
    this.zones = const [0, 0, 0, 0, 0],
    this.rpe = 6,
    this.readiness = 0,
    this.plannedSeconds = 0,
    Map<String, int>? feedback,
    this.inHealth = false,
    this.stravaId,
    this.stravaPending = false,
    this.format = WorkoutFormat.circuit,
    this.programDay,
    this.challenge,
    this.hrr,
  }) : feedback = feedback ?? {};

  int get activeSeconds => done.fold(0, (s, d) => s + d.seconds);
  Duration get duration => end.difference(start);
  double get completion => plannedSeconds == 0 ? 1 : (activeSeconds / plannedSeconds).clamp(0, 1).toDouble();

  /// Obciążenie sesji (sRPE): minuty × RPE.
  double get load => duration.inSeconds / 60 * rpe;

  Map<String, dynamic> toJson() => {
        'id': id,
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
        'kind': kind.name,
        'title': title,
        'done': done.map((d) => d.toJson()).toList(),
        'kcal': kcal,
        'avgHr': avgHr,
        'maxHr': maxHr,
        'hr': hr,
        'zones': zones,
        'rpe': rpe,
        'readiness': readiness,
        'planned': plannedSeconds,
        'feedback': feedback,
        'inHealth': inHealth,
        'stravaId': stravaId,
        'stravaPending': stravaPending,
        'format': format.name,
        if (programDay != null) 'programDay': programDay,
        if (challenge != null) 'challenge': challenge,
        if (hrr != null) 'hrr': hrr,
      };

  factory Session.fromJson(Map<String, dynamic> j) => Session(
        id: j['id'] as String,
        start: DateTime.parse(j['start'] as String),
        end: DateTime.parse(j['end'] as String),
        kind: kindOf(j['kind'] as String? ?? ''),
        title: j['title'] as String? ?? '',
        done: ((j['done'] as List?) ?? const [])
            .map((e) => DoneItem.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        kcal: (j['kcal'] as num?)?.toDouble() ?? 0,
        avgHr: (j['avgHr'] as num?)?.toInt(),
        maxHr: (j['maxHr'] as num?)?.toInt(),
        hr: ((j['hr'] as List?) ?? const []).map((e) => (e as num).toInt()).toList(),
        zones: ((j['zones'] as List?) ?? const [0, 0, 0, 0, 0]).map((e) => (e as num).toInt()).toList(),
        rpe: (j['rpe'] as num?)?.toInt() ?? 6,
        readiness: (j['readiness'] as num?)?.toInt() ?? 0,
        plannedSeconds: (j['planned'] as num?)?.toInt() ?? 0,
        feedback: ((j['feedback'] as Map?) ?? const {}).map((k, v) => MapEntry(k as String, (v as num).toInt())),
        inHealth: j['inHealth'] == true,
        stravaId: (j['stravaId'] as num?)?.toInt(),
        stravaPending: j['stravaPending'] == true,
        format: formatOf(j['format'] as String?),
        programDay: j['programDay'] as String?,
        challenge: j['challenge'] as String?,
        hrr: (j['hrr'] as num?)?.toInt(),
      );
}

/// Poranne samopoczucie.
class CheckIn {
  final DateTime at;
  final int feel; // 1–5
  final Set<String> sore; // grupy mięśniowe z zakwasami
  final double? sleepHours; // gdy brak danych z Health Connect

  CheckIn(this.at, this.feel, this.sore, [this.sleepHours]);

  Map<String, dynamic> toJson() => {'at': at.toIso8601String(), 'feel': feel, 'sore': sore.toList(), 'sleep': sleepHours};

  factory CheckIn.fromJson(Map<String, dynamic> j) => CheckIn(
        DateTime.parse(j['at'] as String),
        (j['feel'] as num).toInt(),
        ((j['sore'] as List?) ?? const []).cast<String>().toSet(),
        (j['sleep'] as num?)?.toDouble(),
      );
}

/// Pomiar HRV z paska (RMSSD z odstępów RR) albo z Health Connect.
class HrvMeasure {
  final DateTime at;
  final double rmssd;
  final int restHr;
  final String source; // 'pasek' / 'health'

  HrvMeasure(this.at, this.rmssd, this.restHr, this.source);

  Map<String, dynamic> toJson() => {'at': at.toIso8601String(), 'rmssd': rmssd, 'hr': restHr, 'src': source};

  factory HrvMeasure.fromJson(Map<String, dynamic> j) => HrvMeasure(
        DateTime.parse(j['at'] as String),
        (j['rmssd'] as num).toDouble(),
        (j['hr'] as num?)?.toInt() ?? 0,
        j['src'] as String? ?? 'pasek',
      );
}

/// Dane z Health Connect / HealthKit potrzebne do oceny gotowości.
class HealthSnapshot {
  final double? sleepHours;
  final int? restingHr;
  final List<int> restingHrHistory; // ostatnie 14 dni
  final double? hrv;
  final List<double> hrvHistory;
  final double? weightKg;

  const HealthSnapshot({
    this.sleepHours,
    this.restingHr,
    this.restingHrHistory = const [],
    this.hrv,
    this.hrvHistory = const [],
    this.weightKg,
  });

  static const empty = HealthSnapshot();
}

/// Pomiary ciała (każde pole opcjonalne).
class Measurement {
  final DateTime at;
  final Map<String, double> values; // weight, waist, hips, chest, arm, thigh, fat

  Measurement(this.at, this.values);

  Map<String, dynamic> toJson() => {'at': at.toIso8601String(), 'v': values};

  factory Measurement.fromJson(Map<String, dynamic> j) => Measurement(
        DateTime.parse(j['at'] as String),
        ((j['v'] as Map?) ?? const {}).map((k, v) => MapEntry(k as String, (v as num).toDouble())),
      );
}

const measureLabel = {
  'weight': ('Waga', 'kg'),
  'waist': ('Talia', 'cm'),
  'hips': ('Biodra', 'cm'),
  'chest': ('Klatka', 'cm'),
  'arm': ('Ramię', 'cm'),
  'thigh': ('Udo', 'cm'),
  'fat': ('Tkanka tłuszczowa', '%'),
};

/// Osoba w aplikacji (dane każdej w osobnym pliku).
class UserRef {
  final String id;
  String name;
  UserRef(this.id, this.name);
  Map<String, dynamic> toJson() => {'id': id, 'name': name};
  factory UserRef.fromJson(Map<String, dynamic> j) => UserRef(j['id'] as String, j['name'] as String? ?? '');
}

/// Dzień planu: co i jak ćwiczyć, z którym tygodniem progresji.
class ProgramDay {
  final String id; // np. „w2d3”
  final int week; // od 1
  final int index; // kolejność w tygodniu, od 1
  final DateTime date; // planowany dzień
  final WorkoutKind kind;
  final WorkoutFormat format;
  final int minutes;
  final double load; // mnożnik objętości (tydzień lżejszy < 1)
  String? sessionId; // wykonany trening
  bool skipped;

  ProgramDay({
    required this.id,
    required this.week,
    required this.index,
    required this.date,
    required this.kind,
    required this.format,
    required this.minutes,
    required this.load,
    this.sessionId,
    this.skipped = false,
  });

  bool get done => sessionId != null;
  bool get deload => load < 0.95;

  Map<String, dynamic> toJson() => {
        'id': id,
        'w': week,
        'i': index,
        'd': date.toIso8601String(),
        'k': kind.name,
        'f': format.name,
        'm': minutes,
        'l': load,
        if (sessionId != null) 's': sessionId,
        if (skipped) 'x': true,
      };

  factory ProgramDay.fromJson(Map<String, dynamic> j) => ProgramDay(
        id: j['id'] as String,
        week: (j['w'] as num).toInt(),
        index: (j['i'] as num).toInt(),
        date: DateTime.parse(j['d'] as String),
        kind: kindOf(j['k'] as String),
        format: formatOf(j['f'] as String?),
        minutes: (j['m'] as num).toInt(),
        load: (j['l'] as num).toDouble(),
        sessionId: j['s'] as String?,
        skipped: j['x'] == true,
      );
}

class Program {
  final String id;
  final String name;
  final Goal goal;
  final DateTime start;
  final int weeks;
  final List<int> weekdays; // 1 = pon … 7 = ndz
  final List<ProgramDay> days;
  bool active;
  final String? templateId; // gotowy program z katalogu
  final List<String> prefer; // ćwiczenia, które ten program stawia na pierwszym miejscu
  final bool quiet; // bez skoków

  Program({
    required this.id,
    required this.name,
    required this.goal,
    required this.start,
    required this.weeks,
    required this.weekdays,
    required this.days,
    this.active = true,
    this.templateId,
    this.prefer = const [],
    this.quiet = false,
  });

  int get doneCount => days.where((d) => d.done).length;
  double get progress => days.isEmpty ? 0 : doneCount / days.length;

  /// Następny trening do zrobienia (zaległe najpierw, w kolejności planu).
  ProgramDay? get next {
    for (final d in days) {
      if (!d.done && !d.skipped) return d;
    }
    return null;
  }

  int currentWeek(DateTime now) {
    final n = next;
    if (n != null) return n.week;
    return weeks;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'goal': goal.name,
        'start': start.toIso8601String(),
        'weeks': weeks,
        'weekdays': weekdays,
        'days': days.map((d) => d.toJson()).toList(),
        'active': active,
        if (templateId != null) 'tpl': templateId,
        if (prefer.isNotEmpty) 'prefer': prefer,
        if (quiet) 'quiet': true,
      };

  factory Program.fromJson(Map<String, dynamic> j) => Program(
        id: j['id'] as String,
        name: j['name'] as String,
        goal: Goal.values.firstWhere((g) => g.name == j['goal'], orElse: () => Goal.general),
        start: DateTime.parse(j['start'] as String),
        weeks: (j['weeks'] as num).toInt(),
        weekdays: ((j['weekdays'] as List?) ?? const [1, 3, 5]).map((e) => (e as num).toInt()).toList(),
        days: ((j['days'] as List?) ?? const []).map((e) => ProgramDay.fromJson((e as Map).cast<String, dynamic>())).toList(),
        active: j['active'] != false,
        templateId: j['tpl'] as String?,
        prefer: ((j['prefer'] as List?) ?? const []).cast<String>(),
        quiet: j['quiet'] == true,
      );
}

/// Test formy: maksymalne wyniki i regeneracja tętna.
class FitTest {
  final DateTime at;
  final int? pushups, squats, plank, restHr, hrr;

  FitTest(this.at, {this.pushups, this.squats, this.plank, this.restHr, this.hrr});

  /// Składowe 0–100 (proste skale, ważne do porównania z samym sobą).
  Map<String, int> get parts => {
        if (pushups != null) 'Pompki': (pushups! * 2.5).round().clamp(0, 100),
        if (squats != null) 'Przysiady': (squats! * 100 / 55).round().clamp(0, 100),
        if (plank != null) 'Deska': (plank! * 100 / 180).round().clamp(0, 100),
        if (restHr != null) 'Tętno spoczynkowe': ((90 - restHr!) * 100 / 45).round().clamp(0, 100),
        if (hrr != null) 'Regeneracja tętna': (hrr! * 100 / 40).round().clamp(0, 100),
      };

  int get score {
    final p = parts.values;
    return p.isEmpty ? 0 : (p.reduce((a, b) => a + b) / p.length).round();
  }

  Map<String, dynamic> toJson() => {
        'at': at.toIso8601String(),
        if (pushups != null) 'pu': pushups,
        if (squats != null) 'sq': squats,
        if (plank != null) 'pl': plank,
        if (restHr != null) 'rhr': restHr,
        if (hrr != null) 'hrr': hrr,
      };

  factory FitTest.fromJson(Map<String, dynamic> j) => FitTest(
        DateTime.parse(j['at'] as String),
        pushups: (j['pu'] as num?)?.toInt(),
        squats: (j['sq'] as num?)?.toInt(),
        plank: (j['pl'] as num?)?.toInt(),
        restHr: (j['rhr'] as num?)?.toInt(),
        hrr: (j['hrr'] as num?)?.toInt(),
      );
}

/// Postęp w wyzwaniu: dni zaliczone kolejno (pominięty dzień nie psuje wyzwania).
class ChallengeProgress {
  final String id;
  final DateTime start;
  final Map<int, String> done; // dzień → id treningu
  bool active;

  ChallengeProgress(this.id, this.start, {Map<int, String>? done, this.active = true}) : done = done ?? {};

  int get nextDay => done.isEmpty ? 1 : done.keys.reduce((a, b) => a > b ? a : b) + 1;

  Map<String, dynamic> toJson() =>
      {'id': id, 'start': start.toIso8601String(), 'done': done.map((k, v) => MapEntry('$k', v)), 'active': active};

  factory ChallengeProgress.fromJson(Map<String, dynamic> j) => ChallengeProgress(
        j['id'] as String,
        DateTime.parse(j['start'] as String),
        done: ((j['done'] as Map?) ?? const {}).map((k, v) => MapEntry(int.parse(k as String), v as String)),
        active: j['active'] != false,
      );
}


/// Aktywność spoza Formy (Strava, Health Connect) — liczy się do obciążenia, kalendarza i poziomu.
class ExternalActivity {
  final String id; // źródło:identyfikator, np. strava:123
  final String source; // strava / health
  final String name;
  final String sport; // Run, Ride, Walk, Workout…
  final DateTime start;
  final int minutes;
  final int? avgHr;
  final int? kcal;
  final double? km;

  ExternalActivity({
    required this.id,
    required this.source,
    required this.name,
    required this.sport,
    required this.start,
    required this.minutes,
    this.avgHr,
    this.kcal,
    this.km,
  });

  /// Obciążenie porównywalne z treningiem Formy (minuty × intensywność).
  /// W tej samej skali co [Session.load] (minuty × wysiłek 1–10).
  double get load => minutes * effort;

  /// Szacowany wysiłek 1–10 (z tętna, a bez niego — z rodzaju aktywności).
  double get effort {
    final hr = avgHr;
    if (hr != null && hr > 0) return ((hr - 85) / 9).clamp(2.0, 10.0).toDouble();
    return switch (sportLabel) { 'Bieg' => 7.0, 'Rower' || 'Pływanie' || 'Trening siłowy' => 6.0, 'Spacer' => 3.0, _ => 5.0 };
  }

  /// Mięśnie, które pracowały (do mapy zmęczenia).
  Map<String, double> get muscles => switch (sportLabel) {
        'Bieg' => const {'calves': 1, 'quads': 0.8, 'hamstrings': 0.7, 'glutes': 0.6},
        'Rower' => const {'quads': 1, 'glutes': 0.6, 'calves': 0.5, 'hamstrings': 0.4},
        'Spacer' || 'Wędrówka' => const {'calves': 0.6, 'quads': 0.5, 'glutes': 0.4},
        'Pływanie' => const {'lats': 1, 'shoulders': 0.9, 'triceps': 0.5, 'chest': 0.5},
        _ => const {},
      };

  /// Grupy mięśni (jak w [muscleGroups]).
  List<String> get groups => switch (sportLabel) {
        'Bieg' || 'Rower' || 'Spacer' || 'Wędrówka' => const ['nogi', 'pośladki'],
        'Pływanie' => const ['plecy', 'barki', 'ramiona'],
        _ => const [],
      };

  String get sportLabel => switch (sport.toLowerCase()) {
        'run' || 'trailrun' || 'virtualrun' || 'running' => 'Bieg',
        'ride' || 'virtualride' || 'ebikeride' || 'mountainbikeride' || 'biking' || 'cycling' => 'Rower',
        'walk' || 'walking' => 'Spacer',
        'hike' || 'hiking' => 'Wędrówka',
        'swim' || 'swimming' => 'Pływanie',
        'weighttraining' || 'strength_training' => 'Trening siłowy',
        'yoga' => 'Joga',
        _ => 'Aktywność',
      };

  Map<String, dynamic> toJson() => {
        'id': id,
        'src': source,
        'n': name,
        'sp': sport,
        'at': start.toIso8601String(),
        'min': minutes,
        if (avgHr != null) 'hr': avgHr,
        if (kcal != null) 'kcal': kcal,
        if (km != null) 'km': km,
      };

  factory ExternalActivity.fromJson(Map<String, dynamic> j) => ExternalActivity(
        id: j['id'] as String,
        source: j['src'] as String? ?? 'strava',
        name: j['n'] as String? ?? '',
        sport: j['sp'] as String? ?? 'Workout',
        start: DateTime.parse(j['at'] as String),
        minutes: (j['min'] as num).toInt(),
        avgHr: (j['hr'] as num?)?.toInt(),
        kcal: (j['kcal'] as num?)?.toInt(),
        km: (j['km'] as num?)?.toDouble(),
      );
}

/// Pozycja własnego treningu.
class CustomItem {
  String exId;
  int? reps; // null = na czas
  int seconds; // czas pracy (albo szacunek przy powtórzeniach)
  int rest;
  CustomItem({required this.exId, this.reps, this.seconds = 40, this.rest = 20});

  Map<String, dynamic> toJson() => {'ex': exId, if (reps != null) 'r': reps, 's': seconds, 'p': rest};
  factory CustomItem.fromJson(Map<String, dynamic> j) => CustomItem(
        exId: j['ex'] as String,
        reps: (j['r'] as num?)?.toInt(),
        seconds: (j['s'] as num?)?.toInt() ?? 40,
        rest: (j['p'] as num?)?.toInt() ?? 20,
      );
}

/// Własny trening ułożony z katalogu.
class CustomWorkout {
  String id;
  String name;
  List<CustomItem> items;
  int rounds;
  int roundRest;
  DateTime created;

  CustomWorkout({
    required this.id,
    required this.name,
    List<CustomItem>? items,
    this.rounds = 2,
    this.roundRest = 60,
    DateTime? created,
  })  : items = items ?? [],
        created = created ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'n': name,
        'it': items.map((e) => e.toJson()).toList(),
        'r': rounds,
        'rr': roundRest,
        'c': created.toIso8601String(),
      };

  factory CustomWorkout.fromJson(Map<String, dynamic> j) => CustomWorkout(
        id: j['id'] as String,
        name: j['n'] as String? ?? 'Mój trening',
        items: ((j['it'] as List?) ?? const []).map((e) => CustomItem.fromJson((e as Map).cast<String, dynamic>())).toList(),
        rounds: (j['r'] as num?)?.toInt() ?? 2,
        roundRest: (j['rr'] as num?)?.toInt() ?? 60,
        created: DateTime.tryParse(j['c'] as String? ?? ''),
      );
}

/// Kod do udostępnienia własnego treningu (np. w wiadomości): „FORMA1:” + base64url(JSON).
String customCode(CustomWorkout w) {
  final j = w.toJson()..remove('id')..remove('c');
  return 'FORMA1:${base64Url.encode(utf8.encode(jsonEncode(j)))}';
}

/// Odczyt kodu (toleruje tekst dookoła i podziały linii). Null, gdy kod jest niepoprawny.
CustomWorkout? customFromCode(String text, {required String id, Set<String>? known}) {
  final m = RegExp(r'FORMA1:([A-Za-z0-9_\-=\s]+)').firstMatch(text);
  if (m == null) return null;
  try {
    final raw = m.group(1)!.replaceAll(RegExp(r'\s'), '');
    final j = (jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(raw)))) as Map).cast<String, dynamic>();
    final w = CustomWorkout.fromJson({...j, 'id': id});
    if (known != null) w.items.removeWhere((i) => !known.contains(i.exId));
    return w.items.isEmpty ? null : w;
  } catch (_) {
    return null;
  }
}
