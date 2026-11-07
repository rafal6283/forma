import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:koofr_backup_ui/koofr_backup_ui.dart';

import 'core/app_settings.dart';
import 'core/backup.dart';
import 'core/family.dart';
import 'core/library.dart';
import 'core/reminders.dart';
import 'core/store.dart';
import 'core/voice.dart';
import 'ui/exercise_screen.dart';
import 'ui/history_screen.dart';
import 'ui/home_screen.dart';
import 'ui/onboarding_screen.dart';
import 'ui/muscle_map.dart';
import 'ui/profile_screen.dart';
import 'ui/settings_screen.dart';
import 'ui/splash.dart';
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
  await MuscleShapes.load();
  await Store.instance.load();
  await AppSettings.instance.load();
  final p = Store.instance.profile;
  Voice.instance
    ..enabled = p.voice
    ..beeps = p.beeps;
  runApp(const FormaApp());
  Store.onSessionAdded = () {
    unawaited(Reminders.instance.reschedule());
    unawaited(Family.instance.publish());
  };
  unawaited(Reminders.instance.reschedule());
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

class _FormaAppState extends State<FormaApp> with WidgetsBindingObserver {
  final settings = AppSettings.instance;
  bool _splash = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    settings.addListener(_onSettings);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    settings.removeListener(_onSettings);
    super.dispose();
  }

  void _onSettings() => setState(() {});

  @override
  void didChangePlatformBrightness() {
    if (settings.theme == 'system') setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final platform = WidgetsBinding.instance.platformDispatcher.platformBrightness;
    C.light = resolveLight(settings.theme, platform);
    final theme = formaTheme();
    // klucz z motywem: zmiana motywu przebudowuje wszystkie ekrany z nową paletą
    return MaterialApp(
      key: ValueKey('theme-${C.light}'),
      title: 'Forma',
      debugShowCheckedModeBanner: false,
      theme: theme,
      darkTheme: theme,
      themeMode: C.light ? ThemeMode.light : ThemeMode.dark,
      locale: const Locale('pl'),
      supportedLocales: const [Locale('pl')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // przełączenie osoby podmienia cały ekran (nowa osoba zaczyna od wprowadzenia)
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 450),
        child: _splash
            ? SplashScreen(key: const ValueKey('splash'), onDone: () => setState(() => _splash = false))
            : ListenableBuilder(
                key: const ValueKey('app'),
                listenable: Store.instance,
                builder: (context, _) => Store.instance.profile.onboarded
                    ? Shell(key: ValueKey(Store.instance.userId))
                    : OnboardingScreen(key: ValueKey('ob-${Store.instance.userId}'), onDone: () => setState(() {})),
              ),
      ),
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  // zapamiętana karta — zmiana motywu przebudowuje aplikację, a użytkownik zostaje w ustawieniach
  static int _tab = 0;
  int get tab => _tab;
  set tab(int v) => _tab = v;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(index: tab, children: const [
          HomeScreen(),
          LibraryScreen(),
          HistoryScreen(),
          ProfileScreen(),
          SettingsScreen(),
        ]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (i) => setState(() => tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.today_outlined), selectedIcon: Icon(Icons.today), label: 'Dziś'),
            NavigationDestination(
                icon: Icon(Icons.fitness_center_outlined), selectedIcon: Icon(Icons.fitness_center), label: 'Ćwiczenia'),
            NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Postępy'),
            NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Ty'),
            NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Ustawienia'),
          ],
        ),
      );
}
