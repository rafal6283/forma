import 'dart:math' as math;

import 'library.dart';
import 'models.dart';
import 'store.dart';

/// Gotowy program: nazwa, tydzień treningowy i ćwiczenia, na których się skupia.
class ProgramTemplate {
  final String id, name, desc;
  final int weeks;
  final int minutes;
  final List<(WorkoutKind, WorkoutFormat)> week;
  final List<String> prefer;
  final Set<String> needs; // sprzęt wymagany
  final bool quiet;
  final int level; // dla kogo (1 = początkujący)

  const ProgramTemplate({
    required this.id,
    required this.name,
    required this.desc,
    required this.weeks,
    required this.week,
    this.minutes = 30,
    this.prefer = const [],
    this.needs = const {},
    this.quiet = false,
    this.level = 2,
  });
}

const programTemplates = <ProgramTemplate>[
  ProgramTemplate(
    id: 'start',
    name: 'Start od zera',
    desc: 'Łagodne wejście w regularny ruch: całe ciało, technika podstawowych ćwiczeń i mobilność.',
    weeks: 4,
    minutes: 20,
    level: 1,
    week: [
      (WorkoutKind.fullBody, WorkoutFormat.circuit),
      (WorkoutKind.mobility, WorkoutFormat.flow),
      (WorkoutKind.fullBody, WorkoutFormat.strengthIntervals),
    ],
    prefer: ['squat', 'knee_pushups', 'wall_pushup', 'glute_bridge', 'dead_bug', 'bird_dog', 'step_jacks', 'box_squat'],
  ),
  ProgramTemplate(
    id: 'pushups100',
    name: 'Droga do 100 pompek',
    desc: 'Pompki w seriach, warianty od kolan po diamentowe, mocny core. Cel: 100 pompek w kilku seriach.',
    weeks: 6,
    minutes: 25,
    week: [
      (WorkoutKind.upper, WorkoutFormat.sets),
      (WorkoutKind.core, WorkoutFormat.circuit),
      (WorkoutKind.upper, WorkoutFormat.supersets),
    ],
    prefer: ['pushups', 'knee_pushups', 'incline_pushups', 'diamond_pushups', 'wide_pushups', 'decline_pushups', 'plank', 'high_plank'],
  ),
  ProgramTemplate(
    id: 'pullup',
    name: 'Pierwsze podciągnięcie',
    desc: 'Zwisy, ściąganie łopatek, opuszczanie i podciąganie australijskie — krok po kroku do pełnego podciągnięcia.',
    weeks: 6,
    needs: {'bar'},
    week: [
      (WorkoutKind.back, WorkoutFormat.supersets),
      (WorkoutKind.core, WorkoutFormat.circuit),
      (WorkoutKind.back, WorkoutFormat.sets),
    ],
    prefer: ['scap_pulls', 'dead_hang', 'negative_pullups', 'inverted_row', 'door_row', 'superman_pull', 'chin_ups', 'pullups', 'hanging_knee_raise'],
  ),
  ProgramTemplate(
    id: 'back',
    name: 'Zdrowe plecy',
    desc: 'Stabilizacja, mobilność kręgosłupa i wzmocnienie mięśni grzbietu. Bez skoków.',
    weeks: 4,
    minutes: 25,
    level: 1,
    quiet: true,
    week: [
      (WorkoutKind.mobility, WorkoutFormat.flow),
      (WorkoutKind.core, WorkoutFormat.circuit),
      (WorkoutKind.back, WorkoutFormat.circuit),
    ],
    prefer: ['bird_dog', 'dead_bug', 'cat_cow', 'glute_bridge', 'superman', 'reverse_angels', 'prone_y', 'childs_pose', 'side_plank_knee', 'thread_needle'],
  ),
  ProgramTemplate(
    id: 'legs',
    name: 'Mocne nogi i pośladki',
    desc: 'Przysiady, wykroki, mostki i martwe ciągi w seriach z progresją powtórzeń.',
    weeks: 6,
    week: [
      (WorkoutKind.lower, WorkoutFormat.sets),
      (WorkoutKind.core, WorkoutFormat.circuit),
      (WorkoutKind.lower, WorkoutFormat.supersets),
    ],
    prefer: ['squat', 'split_squat', 'glute_bridge', 'hip_thrust', 'reverse_lunge', 'sl_rdl', 'step_ups', 'wall_sit', 'cossack_squat'],
  ),
  ProgramTemplate(
    id: 'burn',
    name: 'Spalanie w 4 tygodnie',
    desc: 'Tabata, HIIT i obwody — dużo ruchu w krótkim czasie.',
    weeks: 4,
    minutes: 25,
    week: [
      (WorkoutKind.hiit, WorkoutFormat.tabata),
      (WorkoutKind.fullBody, WorkoutFormat.circuit),
      (WorkoutKind.hiit, WorkoutFormat.hiit),
      (WorkoutKind.lower, WorkoutFormat.circuit),
    ],
    prefer: ['burpees', 'mountain_climbers', 'jumping_jacks', 'high_knees', 'jump_squats', 'skaters'],
  ),
  ProgramTemplate(
    id: 'quiet',
    name: 'Cardio bez skoków',
    desc: 'Intensywnie, ale cicho dla sąsiadów: bez podskoków i lądowań.',
    weeks: 4,
    minutes: 25,
    quiet: true,
    week: [
      (WorkoutKind.hiit, WorkoutFormat.hiit),
      (WorkoutKind.fullBody, WorkoutFormat.circuit),
      (WorkoutKind.core, WorkoutFormat.tabata),
    ],
    prefer: ['mountain_climbers', 'shadow_boxing', 'squat_thrust', 'bear_crawl', 'march', 'knee_to_elbow', 'punch_squat'],
  ),
  ProgramTemplate(
    id: 'strength8',
    name: 'Siła w domu',
    desc: 'Klasyczny podział góra/dół i superserie — najlepiej z hantlami lub gumą.',
    weeks: 8,
    minutes: 40,
    level: 3,
    week: [
      (WorkoutKind.upper, WorkoutFormat.sets),
      (WorkoutKind.lower, WorkoutFormat.sets),
      (WorkoutKind.back, WorkoutFormat.supersets),
      (WorkoutKind.arms, WorkoutFormat.supersets),
    ],
  ),
  ProgramTemplate(
    id: 'core',
    name: 'Brzuch i core',
    desc: 'Deski, pilates i tabata na brzuch, a do tego całe ciało raz w tygodniu.',
    weeks: 6,
    minutes: 25,
    week: [
      (WorkoutKind.core, WorkoutFormat.circuit),
      (WorkoutKind.core, WorkoutFormat.tabata),
      (WorkoutKind.fullBody, WorkoutFormat.strengthIntervals),
    ],
    prefer: ['plank', 'side_plank', 'hollow_hold', 'dead_bug', 'hundred', 'reverse_crunch', 'bicycle', 'plank_reach', 'v_ups'],
  ),
  ProgramTemplate(
    id: 'mobility',
    name: 'Mobilność na co dzień',
    desc: 'Krótkie sesje 15 minut: stawy, kręgosłup i rozciąganie.',
    weeks: 4,
    minutes: 15,
    level: 1,
    quiet: true,
    week: [
      (WorkoutKind.mobility, WorkoutFormat.flow),
      (WorkoutKind.stretch, WorkoutFormat.flow),
      (WorkoutKind.mobility, WorkoutFormat.flow),
      (WorkoutKind.stretch, WorkoutFormat.flow),
      (WorkoutKind.mobility, WorkoutFormat.flow),
    ],
  ),
];

/// Wyzwanie: jedno ćwiczenie dzień po dniu, z rosnącym celem.
class ChallengeDef {
  final String id, name, desc, exId;
  final int days;
  final bool seconds; // cel w sekundach (np. deska), inaczej powtórzenia
  final int start, step;
  final int perSet; // maks. powtórzeń/sekund w jednej serii
  final String? easierEx; // wersja dla początkujących

  const ChallengeDef({
    required this.id,
    required this.name,
    required this.desc,
    required this.exId,
    required this.days,
    required this.start,
    required this.step,
    required this.perSet,
    this.seconds = false,
    this.easierEx,
  });

  /// Cel na dzień (co 7. dzień lżej — regeneracja).
  int target(int day) {
    final base = start + step * (day - 1);
    return day % 7 == 0 ? (base * 0.6).round() : base;
  }

  List<int> split(int total) {
    final n = math.max(1, (total / perSet).ceil());
    final per = (total / n).ceil();
    return [for (var i = 0; i < n; i++) i == n - 1 ? total - per * (n - 1) : per];
  }
}

const challengeDefs = <ChallengeDef>[
  ChallengeDef(
    id: 'plank30',
    name: '30 dni deski',
    desc: 'Od 20 sekund do prawie 3 minut. Codziennie kilka sekund dłużej.',
    exId: 'plank',
    days: 30,
    seconds: true,
    start: 20,
    step: 5,
    perSet: 90,
  ),
  ChallengeDef(
    id: 'squat30',
    name: '30 dni przysiadów',
    desc: 'Od 30 do ponad 170 przysiadów dziennie, w seriach po maks. 25.',
    exId: 'squat',
    days: 30,
    start: 30,
    step: 5,
    perSet: 25,
    easierEx: 'box_squat',
  ),
  ChallengeDef(
    id: 'pushup30',
    name: '30 dni pompek',
    desc: 'Od 10 do 68 pompek dziennie. Na początek możesz robić je na kolanach.',
    exId: 'pushups',
    days: 30,
    start: 10,
    step: 2,
    perSet: 15,
    easierEx: 'knee_pushups',
  ),
  ChallengeDef(
    id: 'abs30',
    name: '30 dni brzucha',
    desc: 'Rowerek dzień po dniu: od 20 do 107 powtórzeń.',
    exId: 'bicycle',
    days: 30,
    start: 20,
    step: 3,
    perSet: 30,
  ),
  ChallengeDef(
    id: 'bridge21',
    name: '21 dni mostka',
    desc: 'Pośladki i lędźwie: od 20 do 80 mostków.',
    exId: 'glute_bridge',
    days: 21,
    start: 20,
    step: 3,
    perSet: 25,
  ),
  ChallengeDef(
    id: 'wallsit21',
    name: '21 dni krzesełka',
    desc: 'Krzesełko przy ścianie: od 20 sekund do 2 minut.',
    exId: 'wall_sit',
    days: 21,
    seconds: true,
    start: 20,
    step: 5,
    perSet: 60,
  ),
  ChallengeDef(
    id: 'deadhang21',
    name: '21 dni zwisu',
    desc: 'Zwis na drążku dla chwytu i kręgosłupa: od 15 s do 75 s.',
    exId: 'dead_hang',
    days: 21,
    seconds: true,
    start: 15,
    step: 3,
    perSet: 45,
  ),
];

ChallengeDef? challengeById(String id) {
  for (final c in challengeDefs) {
    if (c.id == id) return c;
  }
  return null;
}

/// Trening na dzień wyzwania: krótka rozgrzewka i serie ćwiczenia.
WorkoutPlan challengePlan(ChallengeDef c, int day, {bool easier = false}) {
  final lib = Library.instance;
  final exId = easier && c.easierEx != null ? c.easierEx! : c.exId;
  final e = lib[exId]!;
  final total = c.target(day);
  final items = <PlanItem>[];
  for (final w in ['arm_circles', 'march', 'hip_circles']) {
    if (lib[w] != null) items.add(PlanItem(exId: w, work: 30, rest: 0, phase: Phase.warmup));
  }
  final sets = c.split(total);
  for (var i = 0; i < sets.length; i++) {
    final last = i == sets.length - 1;
    final reps = c.seconds ? null : sets[i];
    final work = c.seconds ? sets[i] : math.max(15, (sets[i] * e.anim.cycle).round());
    void add(int side) => items.add(PlanItem(
          exId: exId,
          work: work,
          rest: side == 1 ? 5 : (last ? 0 : 45),
          phase: Phase.main,
          side: side,
          round: i + 1,
          rounds: sets.length,
          reps: reps,
          tag: 'Seria ${i + 1}/${sets.length}',
        ));
    if (e.uni) {
      add(1);
      add(2);
    } else {
      add(0);
    }
  }
  return WorkoutPlan(
    kind: WorkoutKind.fullBody,
    format: WorkoutFormat.sets,
    title: '${c.name} · dzień $day',
    items: items,
    readiness: 0,
    intensity: c.seconds ? 'razem $total s' : 'razem $total powtórzeń',
    reasons: [
      'Dzień $day z ${c.days}: ${c.seconds ? '$total s' : '$total powtórzeń'}${sets.length > 1 ? ' w ${sets.length} seriach' : ''}.',
      if (day % 7 == 0) 'Co 7. dzień lżej — mięśnie odpoczywają.',
    ],
    challenge: '${c.id}:$day',
  );
}

/// Odznaki: liczone z historii (nic nie trzeba zapisywać).
class Achievement {
  final String icon, name, desc;
  final bool earned;
  const Achievement(this.icon, this.name, this.desc, this.earned);
}

List<Achievement> badges(Store s) {
  final n = s.sessions.length;
  final secs = s.sessions.fold(0, (a, x) => a + x.duration.inSeconds);
  final reps = s.sessions.fold(0, (a, x) => a + x.done.fold(0, (b, d) => b + (d.reps ?? 0)));
  final early = s.sessions.any((x) => x.start.hour < 7);
  final late = s.sessions.any((x) => x.start.hour >= 21);
  final hiitDone = s.sessions.any((x) => x.format == WorkoutFormat.tabata);
  final programDone = s.program != null && s.program!.next == null && s.program!.doneCount > 0;
  final challengeDone = s.challenges.values.any((c) {
    final d = challengeById(c.id);
    return d != null && c.done.length >= d.days;
  });
  var bestWeekStreak = 0, cur = 0;
  if (s.sessions.isNotEmpty) {
    final first = s.sessions.first.start;
    var monday = DateTime(first.year, first.month, first.day).subtract(Duration(days: first.weekday - 1));
    while (monday.isBefore(DateTime.now())) {
      final next = monday.add(const Duration(days: 7));
      final days = s.sessions.where((x) => !x.start.isBefore(monday) && x.start.isBefore(next)).map((x) => x.start.day).toSet().length;
      cur = days >= s.profile.daysPerWeek ? cur + 1 : 0;
      bestWeekStreak = math.max(bestWeekStreak, cur);
      monday = next;
    }
  }
  return [
    Achievement('🌱', 'Pierwszy krok', 'Pierwszy trening', n >= 1),
    Achievement('🔟', 'Dziesiątka', '10 treningów', n >= 10),
    Achievement('🏅', 'Pięćdziesiątka', '50 treningów', n >= 50),
    Achievement('💯', 'Setka', '100 treningów', n >= 100),
    Achievement('⏱️', '10 godzin', 'Razem 10 h ćwiczeń', secs >= 36000),
    Achievement('🔁', 'Tysiąc powtórzeń', 'Razem 1000 powtórzeń w seriach', reps >= 1000),
    Achievement('🔥', 'Miesiąc w rytmie', '4 tygodnie z rzędu z celem treningów', bestWeekStreak >= 4),
    Achievement('⚡', 'Tabata', 'Pierwsza tabata', hiitDone),
    Achievement('📅', 'Plan ukończony', 'Cały plan wielotygodniowy', programDone),
    Achievement('🏆', 'Wyzwanie ukończone', 'Wszystkie dni wyzwania', challengeDone),
    Achievement('📏', 'Znam swoją formę', 'Pierwszy test formy', s.tests.isNotEmpty),
    Achievement('🌅', 'Ranny ptaszek', 'Trening przed 7:00', early),
    Achievement('🌙', 'Nocny marek', 'Trening po 21:00', late),
  ];
}
