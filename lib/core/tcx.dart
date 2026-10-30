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
  final per = <String, (int, int)>{}; // id → (serie, sekundy)
  for (final d in s.done) {
    final e = lib[d.exId];
    if (e == null || e.type == ExType.warmup || e.type == ExType.stretch) continue;
    final cur = per[d.exId] ?? (0, 0);
    per[d.exId] = (cur.$1 + (d.side == 2 ? 0 : 1), cur.$2 + d.seconds);
  }
  final lines = <String>[
    for (final e in per.entries)
      '• ${lib[e.key]!.name}: ${e.value.$1 > 1 ? '${e.value.$1} × ' : ''}${(e.value.$2 / (e.value.$1 == 0 ? 1 : e.value.$1)).round()} s',
  ];
  return [
    '${s.title} — Forma',
    ...lines,
    [
      'RPE ${s.rpe}/10',
      if (s.readiness > 0) 'gotowość ${s.readiness}/100',
      if (s.avgHr != null) 'śr. tętno ${s.avgHr}',
    ].join(' · '),
  ].join('\n');
}
