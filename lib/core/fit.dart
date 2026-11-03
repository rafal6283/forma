import 'dart:typed_data';

import 'library.dart';
import 'models.dart';

/// Plik FIT (format zegarków Garmin) z treningu: serie z rodzajem ćwiczenia, powtórzeniami i czasem
/// oraz tętno z opaski. Do ręcznego wgrania na strava.com/upload — Strava odczytuje serie i rysuje mapę mięśni.
/// Algorytm bajt w bajt jak tool/fit_export.py (sprawdzony dekoderem Garmin FIT SDK).
class FitWriter {
  static const _epoch = 631065600; // 1989-12-31 00:00 UTC
  static const _enum = (0x00, 1), _u8 = (0x02, 1), _u16 = (0x84, 2), _u32 = (0x86, 4), _u32z = (0x8C, 4);

  static const _crcTable = [
    0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401, //
    0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400,
  ];

  static int crc16(List<int> data, [int crc = 0]) {
    for (final b in data) {
      var tmp = _crcTable[crc & 0xF];
      crc = (crc >> 4) & 0x0FFF;
      crc = crc ^ tmp ^ _crcTable[b & 0xF];
      tmp = _crcTable[crc & 0xF];
      crc = (crc >> 4) & 0x0FFF;
      crc = crc ^ tmp ^ _crcTable[(b >> 4) & 0xF];
    }
    return crc;
  }

  // komunikat: (lokalny numer, globalny numer, pola (numer, (typ bazowy, rozmiar)))
  static final _msgs = <String, (int, int, List<(int, (int, int))>)>{
    'file_id': (0, 0, [(0, _enum), (1, _u16), (2, _u16), (3, _u32z), (4, _u32)]),
    'event': (1, 21, [(253, _u32), (0, _enum), (1, _enum)]),
    'record': (2, 20, [(253, _u32), (3, _u8)]),
    'set': (3, 225, [(254, _u32), (0, _u32), (3, _u16), (4, _u16), (5, _u8), (6, _u32), (7, _u16), (8, _u16), (10, _u16)]),
    'lap': (
      4,
      19,
      [(253, _u32), (0, _enum), (1, _enum), (2, _u32), (7, _u32), (8, _u32), (11, _u16), (15, _u8), (16, _u8), (25, _enum), (39, _enum)]
    ),
    'session': (
      5,
      18,
      [(253, _u32), (0, _enum), (1, _enum), (2, _u32), (5, _enum), (6, _enum), (7, _u32), (8, _u32), (11, _u16), (16, _u8), (17, _u8), (25, _u16), (26, _u16)]
    ),
    'activity': (6, 34, [(253, _u32), (0, _u32), (1, _u16), (2, _enum), (3, _enum), (4, _enum), (5, _u32)]),
  };

  final _buf = BytesBuilder();
  final _defined = <String>{};

  void _put(int v, int size) {
    for (var i = 0; i < size; i++) {
      _buf.addByte((v >> (8 * i)) & 0xFF);
    }
  }

  static int _invalid(int bt) => switch (bt) {
        0x00 || 0x02 => 0xFF,
        0x84 => 0xFFFF,
        0x86 => 0xFFFFFFFF,
        _ => 0,
      };

  void msg(String name, List<int?> values) {
    final (local, glob, fields) = _msgs[name]!;
    if (_defined.add(name)) {
      _buf.add([0x40 | local, 0, 0]);
      _put(glob, 2);
      _buf.addByte(fields.length);
      for (final (num, (bt, size)) in fields) {
        _buf.add([num, size, bt]);
      }
    }
    _buf.addByte(local);
    for (var i = 0; i < fields.length; i++) {
      final (_, (bt, size)) = fields[i];
      _put(values[i] ?? _invalid(bt), size);
    }
  }

  Uint8List bytes() {
    final data = _buf.toBytes();
    final h = BytesBuilder()
      ..add([14, 0x20])
      ..add([2132 & 0xFF, 2132 >> 8])
      ..add([for (var i = 0; i < 4; i++) (data.length >> (8 * i)) & 0xFF])
      ..add('.FIT'.codeUnits);
    final header = h.toBytes();
    final hc = crc16(header);
    final body = BytesBuilder()
      ..add(header)
      ..add([hc & 0xFF, hc >> 8])
      ..add(data);
    final all = body.toBytes();
    final c = crc16(all);
    return Uint8List.fromList([...all, c & 0xFF, c >> 8]);
  }

  static int ts(DateTime d) => d.toUtc().millisecondsSinceEpoch ~/ 1000 - _epoch;
}

/// Rodzaj aktywności w FIT: trening siłowy albo HIIT (sport = training).
int fitSubSport(WorkoutKind k) => switch (k) {
      WorkoutKind.hiit => 70,
      WorkoutKind.stretch || WorkoutKind.mobility => 26,
      _ => 20,
    };

/// Plik FIT treningu z seriami (kategoria ćwiczenia z Garmin FIT SDK).
Uint8List sessionFit(Session s) {
  final lib = Library.instance;
  final w = FitWriter();
  final t0 = FitWriter.ts(s.start), t1 = FitWriter.ts(s.end);
  final elapsed = t1 - t0;
  final serial = (int.tryParse(s.id) ?? s.id.hashCode) & 0xFFFFFFFF;
  w.msg('file_id', [4, 255, 1, serial, t1]);
  w.msg('event', [t0, 0, 0]);
  for (var i = 0; i < s.hr.length; i++) {
    if (i * 5 > elapsed) break;
    if (s.hr[i] > 0) w.msg('record', [t0 + i * 5, s.hr[i]]);
  }
  final sets = <(int, int?, int, int?)>[];
  for (final d in s.done) {
    final e = lib[d.exId];
    if (e == null || d.seconds <= 0) continue;
    sets.add((d.seconds, d.reps != null && d.reps! > 0 ? d.reps : null, e.fitCategory, e.fitSubtype));
  }
  final work = sets.fold(0, (a, x) => a + x.$1);
  final gap = (elapsed - work).clamp(0, 1 << 30) ~/ (sets.isEmpty ? 1 : sets.length);
  var t = t0;
  for (var i = 0; i < sets.length; i++) {
    final (sec, reps, cat, sub) = sets[i];
    w.msg('set', [t + sec, sec * 1000, reps, null, 1, t, cat, sub, i]);
    t += sec + gap;
  }
  w.msg('event', [t1, 0, 4]);
  final sub = fitSubSport(s.kind);
  final kcal = s.kcal.round();
  w.msg('lap', [t1, 9, 1, t0, elapsed * 1000, elapsed * 1000, kcal, s.avgHr, s.maxHr, 10, sub]);
  w.msg('session', [t1, 8, 1, t0, 10, sub, elapsed * 1000, elapsed * 1000, kcal, s.avgHr, s.maxHr, 0, 1]);
  w.msg('activity', [t1, elapsed * 1000, 1, 0, 26, 1, t1 + s.start.timeZoneOffset.inSeconds]);
  return w.bytes();
}
