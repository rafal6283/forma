import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import 'coach.dart';
import 'models.dart';
import 'store.dart';

/// Widżet na ekranie telefonu (Android): dzisiejszy plan, seria, poziom i szybki start.
class WidgetSync {
  WidgetSync._();
  static final instance = WidgetSync._();

  static const android = 'pl.rafal.forma.FormaWidget';

  /// Stuknięcie w widżet (np. 'quick7', 'command', 'today').
  void Function(String what)? onOpen;
  StreamSubscription<Uri?>? _sub;

  bool get _supported => !kIsWeb && Platform.isAndroid;

  /// Adres, którym widżet uruchomił aplikację (np. forma://quick7) — jako 'quick7'.
  Future<String?> launchUri() async {
    if (!_supported) return null;
    try {
      _sub ??= HomeWidget.widgetClicked.listen((u) {
        final w = u?.host;
        if (w != null && w.isNotEmpty) onOpen?.call(w);
      });
      final u = await HomeWidget.initiallyLaunchedFromHomeWidget();
      final w = u?.host;
      return w == null || w.isEmpty ? null : w;
    } catch (_) {
      return null;
    }
  }

  /// Odświeża dane widżetu (po starcie, treningu, zmianie osoby).
  Future<void> update() async {
    if (!_supported) return;
    try {
      final s = Store.instance;
      if (!s.profile.onboarded) return;
      final t = coach();
      final r = t.readiness();
      final (kind, _) = t.recommendKind(r);
      final st = s.streaks;
      final lv = s.level;
      await HomeWidget.saveWidgetData<String>('title', st.trainedToday ? 'Dziś już ćwiczone ✓' : 'Dziś: ${kindLabel[kind]!.toLowerCase()}');
      await HomeWidget.saveWidgetData<String>(
          'sub', 'Gotowość ${r.score}/100 · tydzień ${st.thisWeek}/${st.weekTarget}${st.riskText != null ? ' · seria zagrożona' : ''}');
      await HomeWidget.saveWidgetData<String>('streak', '🔥 ${st.dayStreak}');
      await HomeWidget.saveWidgetData<String>('level', 'Poziom ${lv.level}');
      await HomeWidget.updateWidget(qualifiedAndroidName: android);
    } catch (e) {
      debugPrint('widżet: $e');
    }
  }
}
