import 'models.dart';

/// Trening opisany zwykłym zdaniem, np. „20 minut na brzuch, bez skakania, cicho, z hantlami”.
class WorkoutCommand {
  final int? minutes;
  final WorkoutKind? kind;
  final WorkoutFormat? format;
  final bool quiet; // bez skoków
  final double load; // 0,85 lekko · 1 · 1,1 mocno
  final Set<String>? equipment; // null = jak w profilu
  final bool? warmup;
  final List<String> understood; // co rozpoznano (do pokazania)

  const WorkoutCommand({
    this.minutes,
    this.kind,
    this.format,
    this.quiet = false,
    this.load = 1,
    this.equipment,
    this.warmup,
    this.understood = const [],
  });

  bool get isEmpty => understood.isEmpty;
}

String _norm(String s) => s
    .toLowerCase()
    .replaceAll('ą', 'a')
    .replaceAll('ć', 'c')
    .replaceAll('ę', 'e')
    .replaceAll('ł', 'l')
    .replaceAll('ń', 'n')
    .replaceAll('ó', 'o')
    .replaceAll('ś', 's')
    .replaceAll('ź', 'z')
    .replaceAll('ż', 'z');

const _numbers = {
  'piec': 5, 'dziesiec': 10, 'pietnascie': 15, 'dwadziescia': 20, 'dwadziescia piec': 25,
  'trzydziesci': 30, 'czterdziesci': 40, 'czterdziesci piec': 45, 'piecdziesiat': 50, 'szescdziesiat': 60,
};

/// Rozpoznanie polecenia (lokalnie, bez internetu). Zwraca puste polecenie, gdy nic nie pasuje.
WorkoutCommand parseCommand(String text, Set<String> owned) {
  final t = _norm(text);
  bool has(List<String> words) => words.any(t.contains);
  final u = <String>[];

  // czas
  int? minutes;
  final m = RegExp(r'(\d{1,3})\s*(min|minut|m\b|\')').firstMatch(t) ?? RegExp(r'^\s*(\d{1,3})\s*$').firstMatch(t);
  if (m != null) {
    minutes = int.parse(m.group(1)!);
  } else if (has(['pol godziny', 'polgodzin'])) {
    minutes = 30;
  } else if (has(['kwadrans'])) {
    minutes = 15;
  } else if (has(['godzine', 'godzina'])) {
    minutes = 60;
  } else {
    for (final e in (_numbers.entries.toList()..sort((a, b) => b.key.length.compareTo(a.key.length)))) {
      if (RegExp('\\b${e.key}\\s*min').hasMatch(t)) {
        minutes = e.value;
        break;
      }
    }
  }
  if (minutes != null) {
    minutes = minutes.clamp(5, 90);
    u.add('$minutes min');
  }

  // partia / rodzaj
  WorkoutKind? kind;
  const kinds = <(List<String>, WorkoutKind)>[
    (['rozciag', 'stretch'], WorkoutKind.stretch),
    (['mobiln', 'joga', 'yoga', 'staw'], WorkoutKind.mobility),
    (['brzuch', 'core', 'kaloryfer', 'mięśnie głębokie', 'miesnie glebokie'], WorkoutKind.core),
    (['nogi', 'posladk', 'pupa', 'uda', 'lydk'], WorkoutKind.lower),
    (['plecy', 'grzbiet'], WorkoutKind.back),
    (['rece', 'ramion', 'biceps', 'triceps'], WorkoutKind.arms),
    (['klatk', 'gora ciala', 'gorna', 'barki'], WorkoutKind.upper),
    (['kondycj', 'cardio', 'kardio', 'spal', 'hiit', 'interwal', 'pot'], WorkoutKind.hiit),
    (['cale cialo', 'calosc', 'ogolny', 'full'], WorkoutKind.fullBody),
  ];
  for (final (words, k) in kinds) {
    if (has(words)) {
      kind = k;
      u.add(kindLabel[k]!.toLowerCase());
      break;
    }
  }

  // format
  WorkoutFormat? format;
  const formats = <(List<String>, WorkoutFormat)>[
    (['tabat'], WorkoutFormat.tabata),
    (['drop'], WorkoutFormat.dropSets),
    (['superser'], WorkoutFormat.supersets),
    (['obwod', 'stacj'], WorkoutFormat.circuit),
    (['seri'], WorkoutFormat.sets),
  ];
  for (final (words, f) in formats) {
    if (has(words)) {
      format = f;
      u.add(formatLabel[f]!.toLowerCase());
      break;
    }
  }

  final quiet = has(['bez skak', 'bez skok', 'cicho', 'sasiad', 'bez podskok', 'w bloku', 'noc']);
  if (quiet) u.add('bez skoków');

  var load = 1.0;
  if (has(['lekk', 'latw', 'spokojn', 'delikat', 'zmeczon', 'regenerac'])) {
    load = 0.85;
    u.add('lżej');
  } else if (has(['mocn', 'ciezk', 'intensywn', 'wycisk', 'na maxa', 'na maksa'])) {
    load = 1.1;
    u.add('mocniej');
  }

  Set<String>? equipment;
  if (has(['bez sprzetu', 'bez hantli', 'bez niczego', 'w podrozy', 'hotel'])) {
    equipment = {};
    u.add('bez sprzętu');
  } else if (has(['hantl', 'ciezark'])) {
    equipment = {...owned, 'db'};
    u.add('z hantlami');
  } else if (has(['gum', 'tasm'])) {
    equipment = {...owned, 'band'};
    u.add('z gumą');
  } else if (has(['kettl', 'odwazni'])) {
    equipment = {...owned, 'kb'};
    u.add('z kettlebell');
  }

  bool? warmup;
  if (has(['bez rozgrzewki'])) {
    warmup = false;
    u.add('bez rozgrzewki');
  }

  return WorkoutCommand(
    minutes: minutes,
    kind: kind,
    format: format,
    quiet: quiet,
    load: load,
    equipment: equipment,
    warmup: warmup,
    understood: u,
  );
}
