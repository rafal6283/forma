import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

import 'models.dart';

/// Health Connect (Android) / Zdrowie (iOS): zapis treningów, odczyt snu, tętna, HRV i wagi.
class HealthSync {
  HealthSync._();
  static final instance = HealthSync._();

  final _h = Health();
  bool _configured = false;
  String? lastError;

  bool get supported => Platform.isAndroid || Platform.isIOS;

  List<HealthDataType> get _readTypes => [
        if (Platform.isAndroid) HealthDataType.SLEEP_SESSION else HealthDataType.SLEEP_ASLEEP,
        HealthDataType.RESTING_HEART_RATE,
        HealthDataType.HEART_RATE,
        if (Platform.isAndroid) HealthDataType.HEART_RATE_VARIABILITY_RMSSD else HealthDataType.HEART_RATE_VARIABILITY_SDNN,
        HealthDataType.WEIGHT,
      ];

  List<HealthDataType> get _writeTypes => [
        HealthDataType.WORKOUT,
        HealthDataType.HEART_RATE,
        HealthDataType.ACTIVE_ENERGY_BURNED,
      ];

  Future<void> _configure() async {
    if (_configured) return;
    await _h.configure();
    _configured = true;
  }

  /// Czy Health Connect jest zainstalowany (na iOS zawsze tak).
  Future<bool> available() async {
    if (!supported) return false;
    try {
      await _configure();
      if (Platform.isIOS) return true;
      return await _h.isHealthConnectAvailable();
    } catch (e) {
      lastError = '$e';
      return false;
    }
  }

  Future<void> installHealthConnect() async {
    try {
      await _configure();
      await _h.installHealthConnect();
    } catch (e) {
      lastError = '$e';
    }
  }

  Future<bool> authorize() async {
    if (!supported) return false;
    try {
      await _configure();
      final types = [..._readTypes, ..._writeTypes];
      final perms = [
        for (final _ in _readTypes) HealthDataAccess.READ,
        for (final _ in _writeTypes) HealthDataAccess.READ_WRITE,
      ];
      final ok = await _h.requestAuthorization(types, permissions: perms);
      lastError = ok ? null : 'Nie przyznano dostępu.';
      return ok;
    } catch (e) {
      lastError = '$e';
      debugPrint('Health: $e');
      return false;
    }
  }

  /// Sen ostatniej nocy, tętno spoczynkowe, HRV i waga.
  Future<HealthSnapshot> snapshot() async {
    if (!supported) return HealthSnapshot.empty;
    try {
      await _configure();
      final now = DateTime.now();
      final from = now.subtract(const Duration(days: 15));
      final pts = await _h.getHealthDataFromTypes(types: _readTypes, startTime: from, endTime: now);
      pts.sort((a, b) => a.dateFrom.compareTo(b.dateFrom));

      // sen: sesje kończące się dziś (po 15:00 dnia poprzedniego)
      final nightStart = DateTime(now.year, now.month, now.day).subtract(const Duration(hours: 9));
      var sleepMin = 0;
      for (final p in pts) {
        if ((p.type == HealthDataType.SLEEP_SESSION || p.type == HealthDataType.SLEEP_ASLEEP) &&
            p.dateTo.isAfter(nightStart)) {
          sleepMin += p.dateTo.difference(p.dateFrom).inMinutes;
        }
      }

      double? num_(HealthDataPoint p) {
        final v = p.value;
        return v is NumericHealthValue ? v.numericValue.toDouble() : null;
      }

      // tętno spoczynkowe: dzienne wartości (lub najniższe tętno z dnia, gdy zegarek ich nie zapisuje)
      final restByDay = <String, double>{};
      final minHrByDay = <String, double>{};
      final hrvByDay = <String, double>{};
      double? weight;
      for (final p in pts) {
        final d = '${p.dateFrom.year}-${p.dateFrom.month}-${p.dateFrom.day}';
        final v = num_(p);
        if (v == null) continue;
        switch (p.type) {
          case HealthDataType.RESTING_HEART_RATE:
            restByDay[d] = v;
          case HealthDataType.HEART_RATE:
            if (v > 30) minHrByDay[d] = minHrByDay[d] == null ? v : (v < minHrByDay[d]! ? v : minHrByDay[d]!);
          case HealthDataType.HEART_RATE_VARIABILITY_RMSSD:
          case HealthDataType.HEART_RATE_VARIABILITY_SDNN:
            hrvByDay[d] = v;
          case HealthDataType.WEIGHT:
            weight = v;
          default:
            break;
        }
      }
      final today = '${now.year}-${now.month}-${now.day}';
      final rest = restByDay.isNotEmpty ? restByDay : minHrByDay;
      final restHist = rest.entries.where((e) => e.key != today).map((e) => e.value.round()).toList();
      return HealthSnapshot(
        sleepHours: sleepMin > 60 ? sleepMin / 60 : null,
        restingHr: rest[today]?.round(),
        restingHrHistory: restHist,
        hrv: hrvByDay[today],
        hrvHistory: hrvByDay.entries.where((e) => e.key != today).map((e) => e.value).toList(),
        weightKg: weight,
      );
    } catch (e) {
      lastError = '$e';
      debugPrint('Health snapshot: $e');
      return HealthSnapshot.empty;
    }
  }

  static HealthWorkoutActivityType _type(WorkoutKind k) => switch (k) {
        WorkoutKind.hiit => HealthWorkoutActivityType.HIGH_INTENSITY_INTERVAL_TRAINING,
        WorkoutKind.mobility || WorkoutKind.stretch => HealthWorkoutActivityType.OTHER,
        _ => HealthWorkoutActivityType.STRENGTH_TRAINING,
      };

  /// Zapis treningu z tętnem (co 15 s) i kaloriami.
  Future<bool> writeSession(Session s) async {
    if (!supported) return false;
    try {
      await _configure();
      final ok = await _h.writeWorkoutData(
        activityType: _type(s.kind),
        start: s.start,
        end: s.end,
        totalEnergyBurned: s.kcal.round(),
        title: 'Forma: ${s.title}',
      );
      for (var i = 0; i < s.hr.length; i++) {
        final bpm = s.hr[i];
        if (bpm <= 0 || i % 3 != 0) continue; // co 15 s wystarczy
        final t = s.start.add(Duration(seconds: i * 5));
        if (t.isAfter(s.end)) break;
        await _h.writeHealthData(
          value: bpm.toDouble(),
          type: HealthDataType.HEART_RATE,
          startTime: t,
          endTime: t,
        );
      }
      lastError = ok ? null : 'Health Connect odrzucił zapis.';
      return ok;
    } catch (e) {
      lastError = '$e';
      debugPrint('Health write: $e');
      return false;
    }
  }
}
