import 'dart:convert';

import 'library.dart';
import 'models.dart';

/// Plik TCX z treningu (czas, kalorie, tętno co 5 s) — do Stravy i innych serwisów.
String sessionTcx(Session s) {
  String t(DateTime d) => d.toUtc().toIso8601String();
  final secs = s.duration.inSeconds;
  final b = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">')
    ..writeln('  <Activities>')
    ..writeln('    <Activity Sport="Other">')
    ..writeln('      <Id>${t(s.start)}</Id>')
    ..writeln('      <Lap StartTime="${t(s.start)}">')
    ..writeln('        <TotalTimeSeconds>$secs</TotalTimeSeconds>')
    ..writeln('        <DistanceMeters>0</DistanceMeters>')
    ..writeln('        <Calories>${s.kcal.round()}</Calories>');
  if (s.avgHr != null) b.writeln('        <AverageHeartRateBpm><Value>${s.avgHr}</Value></AverageHeartRateBpm>');
  if (s.maxHr != null) b.writeln('        <MaximumHeartRateBpm><Value>${s.maxHr}</Value></MaximumHeartRateBpm>');
  b
    ..writeln('        <Intensity>Active</Intensity>')
    ..writeln('        <TriggerMethod>Manual</TriggerMethod>')
    ..writeln('        <Track>');
  if (s.hr.any((v) => v > 0)) {
    for (var i = 0; i < s.hr.length; i++) {
      final at = s.start.add(Duration(seconds: i * 5));
      if (at.isAfter(s.end)) break;
      b.writeln('          <Trackpoint><Time>${t(at)}</Time>'
          '${s.hr[i] > 0 ? '<HeartRateBpm><Value>${s.hr[i]}</Value></HeartRateBpm>' : ''}</Trackpoint>');
    }
  } else {
    b
      ..writeln('          <Trackpoint><Time>${t(s.start)}</Time></Trackpoint>')
      ..writeln('          <Trackpoint><Time>${t(s.end)}</Time></Trackpoint>');
  }
  b
    ..writeln('        </Track>')
    ..writeln('      </Lap>')
    ..writeln('      <Notes>${_xml(sessionDescription(s))}</Notes>')
    ..writeln('    </Activity>')
    ..writeln('  </Activities>')
    ..writeln('</TrainingCenterDatabase>');
  return b.toString();
}

String _xml(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

/// Opis treningu: ćwiczenia z czasem (jak dopisywane ręcznie w Stravie).
String sessionDescription(Session s) {
  final lib = Library.instance;
  // ćwiczenie → (serie, sekundy, powtórzenia w kolejnych seriach)
  final per = <String, (int, int, List<int>)>{};
  for (final d in s.done) {
    final e = lib[d.exId];
    if (e == null || e.type == ExType.warmup || e.type == ExType.stretch) continue;
    final cur = per[d.exId] ?? (0, 0, <int>[]);
    final first = d.side != 2;
    per[d.exId] = (cur.$1 + (first ? 1 : 0), cur.$2 + d.seconds, [...cur.$3, if (d.reps != null && first) d.reps!]);
  }
  final lines = <String>[
    for (final e in per.entries)
      e.value.$3.isNotEmpty
          ? '• ${lib[e.key]!.name}: ${e.value.$3.length} × ${e.value.$3.join('/')} powt.'
          : '• ${lib[e.key]!.name}: ${e.value.$1 > 1 ? '${e.value.$1} × ' : ''}${(e.value.$2 / (e.value.$1 == 0 ? 1 : e.value.$1)).round()} s',
  ];
  return [
    '${s.title} — Forma (${formatLabel[s.format]})',
    ...lines,
    [
      'RPE ${s.rpe}/10',
      if (s.readiness > 0) 'gotowość ${s.readiness}/100',
      if (s.avgHr != null) 'śr. tętno ${s.avgHr}',
    ].join(' · '),
  ].join('\n');
}

/// Typ aktywności Stravy, który przyjmuje serie (JSON upload) — dla rozciągania/mobilności null.
String? setsSportType(WorkoutKind k) => switch (k) {
      WorkoutKind.hiit => 'HighIntensityIntervalTraining',
      WorkoutKind.stretch || WorkoutKind.mobility => null,
      _ => 'WeightTraining',
    };

/// Trening jako plik JSON Stravy z seriami: rodzaj ćwiczenia, powtórzenia, czas; tętno z opaski jako strumień.
/// Strava z rodzajów ćwiczeń rysuje mapę pracujących mięśni.
String sessionSetsJson(Session s) {
  final lib = Library.instance;
  String t(DateTime d) => d.toUtc().toIso8601String().replaceFirst(RegExp(r'\.\d+Z$'), 'Z');
  final sets = <Map<String, dynamic>>[];
  var active = 0;
  for (final d in s.done) {
    final e = lib[d.exId];
    if (e == null || d.seconds <= 0) continue;
    active += d.seconds;
    sets.add({
      'exercise_type': e.strava,
      if (d.reps != null && d.reps! > 0) 'repetitions': d.reps,
      'duration': d.seconds,
    });
  }
  final secs = s.duration.inSeconds;
  final time = <int>[], hr = <int>[];
  for (var i = 0; i < s.hr.length; i++) {
    final at = i * 5;
    if (at > secs) break;
    if (s.hr[i] > 0) {
      time.add(at);
      hr.add(s.hr[i]);
    }
  }
  return jsonEncode({
    'version': '1.0',
    'start_time': t(s.start),
    'utc_offset': s.start.timeZoneOffset.inSeconds,
    'elapsed_time': secs,
    'active_time': active.clamp(0, secs),
    'total_calories': s.kcal.round(),
    'creator': {'name': 'Forma'},
    if (time.length >= 2) 'streams': {'time': time, 'heartrate': hr},
    'sets': sets,
  });
}
