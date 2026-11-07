import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/coach.dart';
import '../core/models.dart';
import 'muscle_map.dart';
import 'theme.dart';

/// Ile godzin do „świeżości” (zmęczenie < 0,3) przy zaniku jak w trenerze (stała 30 h).
int hoursToFresh(double f) => f <= 0.3 ? 0 : (30 * math.log(f / 0.3)).ceil();

/// Mapa zmęczenia mięśni: co pracowało w ostatnich dniach (z biegiem i rowerem) i kiedy odpocznie.
class FatigueScreen extends StatelessWidget {
  const FatigueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final fat = coach().muscleFatigue();
    final list = fat.entries.where((e) => e.value >= 0.05).toList()..sort((a, b) => b.value.compareTo(a.value));
    return Scaffold(
      appBar: AppBar(title: const Text('Zmęczenie mięśni')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
        Text(
          'Z treningów z ostatnich 4 dni oraz biegania i roweru z zegarka. Zmęczenie maleje z czasem. '
          'Trener omija ćwiczenia na mocno zmęczone mięśnie i wybiera te, które odpoczęły.',
          style: TextStyle(color: C.muted, height: 1.35),
        ),
        const SizedBox(height: 12),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: MuscleMap(fat, height: 300, legend: false))),
        const SizedBox(height: 8),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Wszystkie mięśnie wypoczęte — możesz trenować, co chcesz.', style: TextStyle(color: C.muted)),
          )
        else
          Card(
            child: Column(children: [
              for (final e in list)
                ListTile(
                  dense: true,
                  title: Text(muscleLabel[e.key] ?? e.key),
                  subtitle: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: e.value,
                      minHeight: 6,
                      backgroundColor: C.surface2,
                      color: e.value >= 0.6 ? C.bad : (e.value >= 0.3 ? C.warn : C.good),
                    ),
                  ),
                  trailing: SizedBox(
                    width: 92,
                    child: Text(
                      hoursToFresh(e.value) == 0 ? 'gotowe' : 'ok. ${hoursToFresh(e.value)} h',
                      textAlign: TextAlign.right,
                      style: TextStyle(color: C.muted),
                    ),
                  ),
                ),
            ]),
          ),
      ]),
    );
  }
}

/// Karta na ekranie głównym.
class FatigueCard extends StatelessWidget {
  const FatigueCard({super.key});

  @override
  Widget build(BuildContext context) {
    final fat = coach().muscleFatigue();
    final tired = fat.entries.where((e) => e.value >= 0.5).toList()..sort((a, b) => b.value.compareTo(a.value));
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FatigueScreen())),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(children: [
            SizedBox(width: 90, child: MuscleMap(fat, height: 84, legend: false)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Zmęczenie mięśni', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  tired.isEmpty
                      ? 'Wszystko wypoczęte'
                      : '${tired.take(3).map((e) => (muscleLabel[e.key] ?? e.key).toLowerCase()).join(', ')} — trener je oszczędza',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: C.muted, fontSize: 13),
                ),
              ]),
            ),
            const Icon(Icons.chevron_right),
          ]),
        ),
      ),
    );
  }
}
