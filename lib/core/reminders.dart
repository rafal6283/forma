import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'store.dart';

/// Przypomnienia o treningu: codziennie o wybranej godzinie (poza dniami z treningiem)
/// i wieczorne „seria zagrożona”, gdy dziś jeszcze nic, a cel tygodnia lub seria dni są na włosku.
class Reminders {
  Reminders._();
  static final instance = Reminders._();

  final _n = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'reminders',
      'Przypomnienia o treningu',
      channelDescription: 'Przypomnienie o treningu i o zagrożonej serii',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    ),
    iOS: DarwinNotificationDetails(),
  );

  static const _lines = [
    ('Czas na trening', 'Trener ma dla Ciebie plan na dziś — wystarczy kilkanaście minut.'),
    ('Ruszamy?', 'Dzisiejszy trening czeka. Nawet szybkie 7 minut się liczy.'),
    ('Forma czeka', 'Regularność robi wynik. Wpadnij na krótki trening.'),
    ('Dzień treningowy', 'Plan dobrany do Twojej gotowości — sprawdź, co dziś.'),
  ];

  Future<bool> _init() async {
    if (_ready) return true;
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return false;
    try {
      tzdata.initializeTimeZones();
      await _n.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
      _ready = true;
    } catch (e) {
      debugPrint('powiadomienia: $e');
    }
    return _ready;
  }

  /// Prośba o zgodę (Android 13+, iOS). Zwraca, czy można wysyłać.
  Future<bool> requestPermission() async {
    if (!await _init()) return false;
    try {
      if (Platform.isAndroid) {
        final a = _n.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        return await a?.requestNotificationsPermission() ?? true;
      }
      final i = _n.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      return await i?.requestPermissions(alert: true, badge: true, sound: true) ?? false;
    } catch (e) {
      debugPrint('powiadomienia (zgoda): $e');
      return false;
    }
  }

  /// Układa przypomnienia na 7 dni od nowa (po starcie aplikacji, treningu i zmianie ustawień).
  Future<void> reschedule() async {
    if (!await _init()) return;
    try {
      await _n.cancelAll();
      final s = Store.instance;
      final p = s.profile;
      if (!p.reminders) return;
      final st = s.streaks;
      final now = DateTime.now();
      var id = 1;
      for (var i = 0; i < 7; i++) {
        final day = DateTime(now.year, now.month, now.day).add(Duration(days: i));
        if (i == 0 && st.trainedToday) continue;
        final at = day.add(Duration(hours: p.reminderHour));
        final (title, body) = _lines[(day.day + day.month) % _lines.length];
        if (at.isAfter(now)) {
          await _schedule(id++, at, title, i == 0 ? (st.riskText ?? body) : body);
        }
        // wieczorem: seria zagrożona (tylko dziś — jutro sytuacja będzie inna)
        if (i == 0 && st.atRisk) {
          final late = day.add(Duration(hours: (p.reminderHour + 3).clamp(19, 21)));
          if (late.isAfter(now)) {
            await _schedule(id++, late, 'Seria zagrożona 🔥', st.riskText ?? 'Krótki trening uratuje serię.');
          }
        }
      }
    } catch (e) {
      debugPrint('powiadomienia (plan): $e');
    }
  }

  Future<void> _schedule(int id, DateTime at, String title, String body) => _n.zonedSchedule(
        id: id,
        scheduledDate: tz.TZDateTime.from(at, tz.UTC),
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: title,
        body: body,
      );
}
