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
};

/// Ograniczenia: ćwiczenia obciążające te miejsca są pomijane.
const limitLabels = ['kolana', 'plecy', 'nadgarstki', 'barki'];

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
  final int lvl;
  final double met;
  final bool impact, uni, isStatic;
  final String? hold, easier, harder;
  final FigAnim anim;
  final Map<String, double> muscles; // 1 = główny, 0,5 = pomocniczy

  Exercise({
    required this.id,
    required this.name,
    required this.type,
    required this.groups,
    required this.eq,
    required this.stress,
    required this.tips,
    required this.lvl,
    required this.met,
    required this.impact,
    required this.uni,
    required this.isStatic,
    required this.anim,
    this.muscles = const {},
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
    );
  }

  /// Każda pozycja sprzętu musi być dostępna; „db|kb” = wystarczy jedno z nich.
  bool availableWith(Set<String> owned) => eq.every((e) => e.split('|').any(owned.contains));

  bool get needsEquipment => eq.isNotEmpty;

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
  bool stravaAuto; // wysyłaj po treningu
  bool stravaMatch; // uzupełnij aktywność z zegarka zamiast tworzyć nową

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
    this.stravaAuto = true,
    this.stravaMatch = true,
  })  : equipment = equipment ?? {'chair'},
        limits = limits ?? {};

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
        'stravaAuto': stravaAuto,
        'stravaMatch': stravaMatch,
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
        stravaAuto: j['stravaAuto'] != false,
        stravaMatch: j['stravaMatch'] != false,
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

  PlanItem({
    required this.exId,
    required this.work,
    required this.rest,
    required this.phase,
    this.side = 0,
    this.round = 1,
    this.rounds = 1,
  });

  Map<String, dynamic> toJson() =>
      {'ex': exId, 'w': work, 'r': rest, 'p': phase.name, 's': side, 'rd': round, 'rds': rounds};

  factory PlanItem.fromJson(Map<String, dynamic> j) => PlanItem(
        exId: j['ex'] as String,
        work: (j['w'] as num).toInt(),
        rest: (j['r'] as num).toInt(),
        phase: Phase.values.firstWhere((p) => p.name == j['p'], orElse: () => Phase.main),
        side: (j['s'] as num?)?.toInt() ?? 0,
        round: (j['rd'] as num?)?.toInt() ?? 1,
        rounds: (j['rds'] as num?)?.toInt() ?? 1,
      );
}

class WorkoutPlan {
  WorkoutKind kind;
  String title;
  List<PlanItem> items;
  int readiness;
  String intensity;
  List<String> reasons;

  WorkoutPlan({
    required this.kind,
    required this.title,
    required this.items,
    required this.readiness,
    required this.intensity,
    required this.reasons,
  });

  int get seconds => items.fold(0, (s, i) => s + i.work + i.rest);
  int get minutes => (seconds / 60).round();
}

/// Wykonane ćwiczenie w sesji.
class DoneItem {
  final String exId;
  final int seconds;
  final int side;
  DoneItem(this.exId, this.seconds, this.side);
  Map<String, dynamic> toJson() => {'ex': exId, 's': seconds, 'sd': side};
  factory DoneItem.fromJson(Map<String, dynamic> j) =>
      DoneItem(j['ex'] as String, (j['s'] as num).toInt(), (j['sd'] as num?)?.toInt() ?? 0);
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
