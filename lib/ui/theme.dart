import 'package:flutter/material.dart';

/// Paleta Formy: grafit + koralowy akcent energii.
class C {
  static const bg = Color(0xFF0F1115);
  static const surface = Color(0xFF181B22);
  static const surface2 = Color(0xFF232733);
  static const line = Color(0xFF2E3341);
  static const text = Color(0xFFF2F3F5);
  static const muted = Color(0xFF8E94A3);
  static const accent = Color(0xFFFF6A3D);
  static const good = Color(0xFF46D39A);
  static const warn = Color(0xFFFFC24B);
  static const bad = Color(0xFFFF4D5E);
  static const calm = Color(0xFF7FA7FF);

  static const zones = [calm, good, warn, Color(0xFFFF8A3D), bad];
  static Color zone(int z) => zones[(z - 1).clamp(0, 4)];

  static Color readiness(int s) => s < 40
      ? bad
      : s < 60
          ? warn
          : s < 80
              ? good
              : const Color(0xFF2EE6A8);

  static const figure = Color(0xFFF2F3F5);
  static const figureFar = Color(0xFF6E7587);
  static const prop = Color(0xFFB08A5A);
}

ThemeData formaTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: C.accent,
    brightness: Brightness.dark,
    surface: C.surface,
    primary: C.accent,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: C.bg,
    appBarTheme: const AppBarTheme(backgroundColor: C.bg, elevation: 0, centerTitle: false),
    cardTheme: CardThemeData(
      color: C.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    navigationBarTheme: const NavigationBarThemeData(backgroundColor: C.surface, indicatorColor: Color(0x33FF6A3D)),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: C.accent,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 52),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    chipTheme: const ChipThemeData(backgroundColor: C.surface2, side: BorderSide.none),
    dividerColor: C.line,
  );
}

String fmtDur(int seconds) {
  final m = seconds ~/ 60, s = seconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

String fmtMin(int seconds) {
  final m = (seconds / 60).round();
  if (m < 60) return '$m min';
  return '${m ~/ 60} h ${m % 60} min';
}

const _months = ['sty', 'lut', 'mar', 'kwi', 'maj', 'cze', 'lip', 'sie', 'wrz', 'paź', 'lis', 'gru'];
const _days = ['pon', 'wt', 'śr', 'czw', 'pt', 'sob', 'ndz'];

String fmtDate(DateTime d) => '${_days[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';
String fmtTime(DateTime d) => '${d.hour}:${d.minute.toString().padLeft(2, '0')}';
