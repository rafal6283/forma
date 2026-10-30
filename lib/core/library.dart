import 'dart:convert';

import 'package:flutter/services.dart';

import 'figure.dart';
import 'models.dart';

/// Baza ćwiczeń z assets/exercises.json (generowana przez tool/build_exercises.py).
class Library {
  Library._(this.all, this.poses);

  static Library? _i;
  static Library get instance => _i!;

  final List<Exercise> all;
  final Map<String, Pose> poses;
  late final Map<String, Exercise> byId = {for (final e in all) e.id: e};

  static Future<Library> load() async {
    final raw = await rootBundle.loadString('assets/exercises.json');
    return _i = parse(raw);
  }

  /// Bez Fluttera (testy).
  static Library parse(String raw) {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final poses = (j['poses'] as Map).map(
      (k, v) => MapEntry(k as String, Pose.fromJson((v as Map).cast<String, dynamic>())),
    );
    final ex = (j['exercises'] as List)
        .map((e) => Exercise.fromJson((e as Map).cast<String, dynamic>(), poses))
        .toList();
    return _i = Library._(ex, poses);
  }

  Exercise? operator [](String id) => byId[id];
}
