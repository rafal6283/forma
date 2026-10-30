import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:koofr_backup_ui/koofr_backup_ui.dart';

import 'core/backup.dart';
import 'core/library.dart';
import 'core/store.dart';
import 'core/voice.dart';
import 'ui/exercise_screen.dart';
import 'ui/history_screen.dart';
import 'ui/home_screen.dart';
import 'ui/onboarding_screen.dart';
import 'ui/settings_screen.dart';
import 'ui/theme.dart';

/// Kopia na Koofr w tle (Android) — osobny proces, więc dane wczytujemy od nowa.
@pragma('vm:entry-point')
void koofrCallback() => KoofrBackground.dispatch(() async {
      await Store.instance.load();
      return FormaBackup();
    });

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Library.load();
  await Store.instance.load();
  final p = Store.instance.profile;
  Voice.instance
    ..enabled = p.voice
    ..beeps = p.beeps;
  runApp(const FormaApp());
  // kopia Koofr — w tle, bez wpływu na start
  unawaited(() async {
    try {
      await KoofrBackup.setup(FormaBackup());
      await KoofrBackground.start(koofrCallback);
    } catch (e) {
      debugPrint('Koofr: $e');
    }
  }());
}

class FormaApp extends StatefulWidget {
  const FormaApp({super.key});

  @override
  State<FormaApp> createState() => _FormaAppState();
}

class _FormaAppState extends State<FormaApp> {
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Forma',
        debugShowCheckedModeBanner: false,
        theme: formaTheme(),
        darkTheme: formaTheme(),
        themeMode: ThemeMode.dark,
        locale: const Locale('pl'),
        supportedLocales: const [Locale('pl')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Store.instance.profile.onboarded
            ? const Shell()
            : OnboardingScreen(onDone: () => setState(() {})),
      );
}

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int tab = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(index: tab, children: const [
          HomeScreen(),
          LibraryScreen(),
          HistoryScreen(),
          SettingsScreen(),
        ]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (i) => setState(() => tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.today_outlined), selectedIcon: Icon(Icons.today), label: 'Dziś'),
            NavigationDestination(
                icon: Icon(Icons.fitness_center_outlined), selectedIcon: Icon(Icons.fitness_center), label: 'Ćwiczenia'),
            NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Historia'),
            NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Ustawienia'),
          ],
        ),
      );
}
