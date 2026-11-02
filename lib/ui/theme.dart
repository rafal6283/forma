import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

/// Paleta Formy: grafit + koralowy akcent energii.
class C {
  /// Tryb jasny — ustawiany przy starcie i po zmianie w ustawieniach (cała aplikacja jest wtedy przebudowywana).
  static bool light = false;

  static Color get bg => light ? const Color(0xFFF3F4F7) : const Color(0xFF0F1115);
  static Color get surface => light ? const Color(0xFFFFFFFF) : const Color(0xFF181B22);
  static Color get surface2 => light ? const Color(0xFFE8EAF0) : const Color(0xFF232733);
  static Color get line => light ? const Color(0xFFD5D9E1) : const Color(0xFF2E3341);
  static Color get text => light ? const Color(0xFF14161B) : const Color(0xFFF2F3F5);
  static Color get muted => light ? const Color(0xFF626876) : const Color(0xFF8E94A3);
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

  static Color get figure => light ? const Color(0xFF2A2F3A) : const Color(0xFFF2F3F5);
  static Color get figureFar => light ? const Color(0xFFA0A6B3) : const Color(0xFF6E7587);
  static const prop = Color(0xFFB08A5A);
}

/// Wybór motywu: 'system' / 'light' / 'dark'.
bool resolveLight(String mode, Brightness platform) =>
    mode == 'light' || (mode == 'system' && platform == Brightness.light);

ThemeData formaTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: C.accent,
    brightness: C.light ? Brightness.light : Brightness.dark,
    surface: C.surface,
    primary: C.accent,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: C.bg,
    appBarTheme: AppBarTheme(backgroundColor: C.bg, elevation: 0, centerTitle: false),
    cardTheme: CardThemeData(
      color: C.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    navigationBarTheme: NavigationBarThemeData(backgroundColor: C.surface, indicatorColor: const Color(0x33FF6A3D)),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: C.accent,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 52),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    chipTheme: ChipThemeData(backgroundColor: C.surface2, side: BorderSide.none),
    dividerColor: C.line,
    // płynne przejścia między ekranami
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: ZoomPageTransitionsBuilder(allowEnterRouteSnapshotting: false),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: C.light ? const Color(0xFF14161B) : const Color(0xFF2A2F3B),
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
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
