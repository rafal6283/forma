import 'package:flutter_test/flutter_test.dart';
import 'package:forma/core/family.dart';
import 'package:forma/core/models.dart';
import 'package:forma/core/store.dart';

/// Rodzinna rywalizacja (v1.9): karta wyników — tylko liczby, poprawny zapis i odczyt.
void main() {
  test('karta rodziny: zapis i odczyt bez zmian', () {
    final c = FamilyCard(
      name: 'Rafał', weekDays: 3, weekMinutes: 95, monthDays: 9, streak: 2, level: 4, xp: 1234,
      challenges: const {'plank30': 7}, at: DateTime(2026, 11, 20, 19),
    );
    final back = FamilyCard.fromJson(c.toJson());
    expect(back.toJson(), c.toJson());
    // stara lub niepełna karta nie wywraca aplikacji
    final empty = FamilyCard.fromJson(const {});
    expect((empty.name, empty.level, empty.challenges), ('', 1, isEmpty));
  });

  test('moja karta: trening z tego tygodnia liczy się do minut tygodnia', () {
    final s = Store.instance;
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, 0, 1);
    s.sessions.add(Session(
      id: 'f1', start: start, end: start.add(const Duration(minutes: 25)), kind: WorkoutKind.upper,
      title: 'Rano', done: const [], kcal: 150,
    ));
    final c = FamilyCard.mine(name: 'Ja');
    expect(c.name, 'Ja');
    expect(c.weekDays, greaterThanOrEqualTo(1));
    expect(c.weekMinutes, greaterThanOrEqualTo(25));
    expect(c.toJson().keys, isNot(contains('hr'))); // bez danych zdrowotnych
  });
}
