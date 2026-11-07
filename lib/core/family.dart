import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:koofr_backup_ui/koofr_backup_ui.dart';

import 'catalog.dart';
import 'store.dart';

/// Wyniki jednej osoby do rodzinnej rywalizacji (tylko liczby — bez szczegółów zdrowia).
class FamilyCard {
  final String name;
  final int weekDays, weekMinutes, monthDays, streak, level, xp;
  final Map<String, int> challenges; // wyzwanie → zaliczone dni
  final DateTime at;

  const FamilyCard({
    required this.name,
    required this.weekDays,
    required this.weekMinutes,
    required this.monthDays,
    required this.streak,
    required this.level,
    required this.xp,
    required this.challenges,
    required this.at,
  });

  Map<String, Object?> toJson() => {
        'v': 1,
        'n': name,
        'wd': weekDays,
        'wm': weekMinutes,
        'md': monthDays,
        'st': streak,
        'lv': level,
        'xp': xp,
        'ch': challenges,
        'at': at.toIso8601String(),
      };

  factory FamilyCard.fromJson(Map<String, Object?> j) => FamilyCard(
        name: j['n'] as String? ?? '',
        weekDays: (j['wd'] as num?)?.toInt() ?? 0,
        weekMinutes: (j['wm'] as num?)?.toInt() ?? 0,
        monthDays: (j['md'] as num?)?.toInt() ?? 0,
        streak: (j['st'] as num?)?.toInt() ?? 0,
        level: (j['lv'] as num?)?.toInt() ?? 1,
        xp: (j['xp'] as num?)?.toInt() ?? 0,
        challenges: ((j['ch'] as Map?) ?? const {}).map((k, v) => MapEntry(k as String, (v as num).toInt())),
        at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
      );

  /// Moje bieżące wyniki.
  static FamilyCard mine({String? name}) {
    final s = Store.instance;
    final st = s.streaks;
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    var wm = 0;
    st.minutesByDay.forEach((d, m) {
      if (!d.isBefore(monday)) wm += m;
    });
    final lv = s.level;
    return FamilyCard(
      name: name ?? s.profile.name,
      weekDays: st.thisWeek,
      weekMinutes: wm,
      monthDays: st.month(now).$1,
      streak: st.dayStreak,
      level: lv.level,
      xp: lv.xp,
      challenges: {
        for (final c in challengeDefs)
          if (s.challenges[c.id]?.active == true) c.id: s.challenges[c.id]!.done.length,
      },
      at: now,
    );
  }
}

/// Rodzinna rywalizacja przez wspólne konto Koofr: każdy na swoim telefonie,
/// wyniki wymieniane za obopólną zgodą (zaszyfrowane, przez moduł podglądu Koofr).
class Family {
  Family._();
  static final instance = Family._();

  static const scope = {'forma': true};

  KoofrSync? get sync {
    try {
      return KoofrBackup.instance.sync;
    } catch (_) {
      return null;
    }
  }

  bool get ready => sync?.ready == true;

  /// Wysyła moje wyniki osobom z aktywnym podglądem. Zwraca liczbę osób.
  Future<int> publish() async {
    final s = sync;
    if (s == null || !s.ready) return 0;
    try {
      final me = await s.me();
      final card = FamilyCard.mine(name: me?.name);
      return await s.publishShares((viewer, scope) async => utf8.encode(jsonEncode(card.toJson())));
    } catch (e) {
      debugPrint('Rodzina: $e');
      return 0;
    }
  }

  Future<FamilyCard?> fetch(String ownerId) async {
    final r = await sync?.fetchShared(ownerId);
    if (r == null) return null;
    try {
      return FamilyCard.fromJson((jsonDecode(utf8.decode(r.$1)) as Map).cast<String, Object?>());
    } catch (_) {
      return null;
    }
  }

  /// Zaproszenie lub przyjęcie: pokazuję swoje wyniki i proszę o wyniki drugiej osoby.
  Future<void> connect(String id) async {
    final s = sync!;
    await s.allowView(id, scope);
    await s.requestView(id);
    await publish();
  }

  Future<void> disconnect(String id) async {
    final s = sync!;
    await s.revokeAsOwner(id);
    await s.revokeAsViewer(id);
  }
}
