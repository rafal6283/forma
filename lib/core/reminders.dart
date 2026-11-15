import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'store.dart';

const _actionPort = 'forma_actions';

/// Przycisk w powiadomieniu (np. „Pauza” na ekranie blokady) — w osobnym izolacie, przekazany do aplikacji.
@pragma('vm:entry-point')
void notificationBackground(NotificationResponse r) {
  IsolateNameServer.lookupPortByName(_actionPort)?.send(r.actionId ?? r.payload);
}

/// Przypomnienia o treningu: codziennie o wybranej godzinie (poza dniami z treningiem)
/// i wieczorne „seria zagrożona”, gdy dziś jeszcze nic, a cel tygodnia lub seria dni są na włosku.
class Reminders {
  Reminders._();
  static final instance = Reminders._();

  final _n = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  final _port = ReceivePort();

  /// Przycisk w powiadomieniu treningu (actionId: 'pause' / 'next').
  void Function(String action)? onAction;

  /// Stuknięcie powiadomienia (payload, np. 'break' — przerwa na ruch).
  void Function(String payload)? onOpen;

  /// Powiadomienie, którym uruchomiono aplikację (np. przerwa na ruch) — do obsłużenia po starcie.
  String? launchPayload;

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
      IsolateNameServer.removePortNameMapping(_actionPort);
      IsolateNameServer.registerPortWithName(_port.sendPort, _actionPort);
      _port.listen((m) {
        if (m is String) onAction?.call(m);
      });
      await _n.initialize(
        onDidReceiveNotificationResponse: (r) {
          if (r.actionId != null && r.actionId!.isNotEmpty) {
            onAction?.call(r.actionId!);
          } else if (r.payload != null) {
            onOpen?.call(r.payload!);
          }
        },
        onDidReceiveBackgroundNotificationResponse: notificationBackground,
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
      final launch = await _n.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) launchPayload = launch!.notificationResponse?.payload;
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
      final st = s.streaks;
      final now = DateTime.now();
      var id = 1;
      for (var i = 0; i < 7 && p.reminders; i++) {
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
      // przerwy na ruch: dni robocze, co [breakEvery] min w godzinach pracy (iOS: max 64 zaplanowane — 5 dni)
      if (p.moveBreaks) {
        var bid = 100;
        for (var i = 0; i < 5; i++) {
          final day = DateTime(now.year, now.month, now.day).add(Duration(days: i));
          if (day.weekday > 5) continue;
          for (var m = p.breakFrom * 60 + p.breakEvery; m < p.breakTo * 60; m += p.breakEvery) {
            final at = day.add(Duration(minutes: m));
            if (!at.isAfter(now) || bid > 150) continue;
            final (t, b) = _breakLines[(m ~/ p.breakEvery + day.day) % _breakLines.length];
            await _schedule(bid++, at, t, b, payload: 'break');
          }
        }
      }
    } catch (e) {
      debugPrint('powiadomienia (plan): $e');
    }
  }

  static const _breakLines = [
    ('Przerwa na ruch', '3 minuty: barki, kręgosłup, biodra. Stuknij, żeby zacząć.'),
    ('Wstań na chwilę', 'Krótka przerwa od siedzenia — rozruszaj plecy i nogi.'),
    ('Czas się przeciągnąć', 'Kilka ćwiczeń przy biurku dobrze zrobi karkowi i krążeniu.'),
  ];

  // ------------------------------------------------------------ trening na ekranie blokady

  static const _workoutId = 900;

  /// Bieżące ćwiczenie i odliczanie w powiadomieniu (ekran blokady), z przyciskami Pauza / Dalej.
  Future<void> showWorkout({required String title, required String body, DateTime? endsAt, bool paused = false}) async {
    if (!await _init()) return;
    try {
      await _n.show(
        id: _workoutId,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'workout',
            'Trening w toku',
            channelDescription: 'Bieżące ćwiczenie na ekranie blokady',
            importance: Importance.low,
            priority: Priority.low,
            ongoing: true,
            autoCancel: false,
            onlyAlertOnce: true,
            silent: true,
            visibility: NotificationVisibility.public,
            category: AndroidNotificationCategory.workout,
            showWhen: endsAt != null && !paused,
            when: endsAt?.millisecondsSinceEpoch,
            usesChronometer: endsAt != null && !paused,
            chronometerCountDown: true,
            actions: [
              AndroidNotificationAction('pause', paused ? 'Wznów' : 'Pauza', cancelNotification: false),
              const AndroidNotificationAction('next', 'Dalej', cancelNotification: false),
            ],
          ),
          iOS: const DarwinNotificationDetails(presentAlert: false, presentSound: false, presentList: true),
        ),
      );
    } catch (e) {
      debugPrint('powiadomienie treningu: $e');
    }
  }

  Future<void> hideWorkout() async {
    if (!_ready) return;
    try {
      await _n.cancel(id: _workoutId);
    } catch (_) {}
  }

  Future<void> _schedule(int id, DateTime at, String title, String body, {String? payload}) => _n.zonedSchedule(
        payload: payload,
        id: id,
        scheduledDate: tz.TZDateTime.from(at, tz.UTC),
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: title,
        body: body,
      );
}
