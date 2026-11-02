import 'package:flutter/material.dart';

import '../core/library.dart';
import '../core/models.dart';
import '../core/store.dart';
import 'theme.dart';

/// Dolegliwości i kontuzje: trener omija ćwiczenia obciążające dane miejsce i daje zamienniki.
class InjuriesScreen extends StatefulWidget {
  const InjuriesScreen({super.key});

  @override
  State<InjuriesScreen> createState() => _InjuriesScreenState();
}

class _InjuriesScreenState extends State<InjuriesScreen> {
  final store = Store.instance;
  Profile get p => store.profile;

  @override
  void initState() {
    super.initState();
    // dolegliwości czasowe po terminie znikają
    final now = DateTime.now();
    final expired = [for (final e in p.limitUntil.entries) if (!e.value.isAfter(now)) e.key];
    if (expired.isNotEmpty) {
      for (final k in expired) {
        p.limits.remove(k);
        p.limitUntil.remove(k);
      }
      store.save();
    }
  }

  int _excluded(String area) => Library.instance.all.where((e) => e.stress.contains(area)).length;

  String _status(String area) {
    if (!p.limits.contains(area)) return 'bez ograniczeń';
    final u = p.limitUntil[area];
    if (u == null) return 'na stałe';
    final left = u.difference(DateTime.now()).inDays + 1;
    return 'jeszcze $left ${left == 1 ? 'dzień' : 'dni'} (do ${fmtDate(u)})';
  }

  Future<void> _edit(String area) async {
    final res = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text('Oszczędzaj: $area', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Trener: ${limitHints[area] ?? ''}. Pomija ${_excluded(area)} ćwiczeń i dobiera zamienniki.',
                style: TextStyle(color: C.muted)),
          ),
          for (final (label, days) in const [
            ('1 tydzień', 7),
            ('2 tygodnie', 14),
            ('4 tygodnie', 28),
            ('Na stałe', 0),
            ('Nie oszczędzaj', -1),
          ])
            ListTile(
              leading: Icon(days < 0 ? Icons.check_circle_outline : (days == 0 ? Icons.all_inclusive : Icons.event)),
              title: Text(label),
              onTap: () => Navigator.pop(c, days),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (res == null) return;
    setState(() {
      if (res < 0) {
        p.limits.remove(area);
        p.limitUntil.remove(area);
      } else {
        p.limits.add(area);
        if (res == 0) {
          p.limitUntil.remove(area);
        } else {
          p.limitUntil[area] = DateTime.now().add(Duration(days: res));
        }
      }
    });
    await store.save();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Dolegliwości i kontuzje')),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
          Text(
            'Zaznacz, co boli albo co leczysz. Trener ominie ćwiczenia, które to miejsce obciążają, '
            'a w planach i programach wstawi zamienniki z tej samej partii. '
            'Dolegliwość czasowa sama wygaśnie. W trakcie treningu powiedz lub stuknij „boli” — zaproponuję zapis.',
            style: TextStyle(color: C.muted, height: 1.35),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(children: [
              for (final a in limitLabels)
                ListTile(
                  leading: Icon(
                    p.activeLimits.contains(a) ? Icons.healing : Icons.circle_outlined,
                    color: p.activeLimits.contains(a) ? C.warn : C.muted,
                  ),
                  title: Text(a[0].toUpperCase() + a.substring(1)),
                  subtitle: Text(_status(a), style: TextStyle(color: C.muted)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _edit(a),
                ),
            ]),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('Bez skoków'),
            subtitle: Text('Cicho dla sąsiadów, oszczędnie dla stawów', style: TextStyle(color: C.muted)),
            value: p.noJumping,
            onChanged: (v) {
              setState(() => p.noJumping = v);
              store.save();
            },
          ),
          const SizedBox(height: 8),
          Text('To nie porada medyczna — przy silnym lub narastającym bólu skonsultuj się z lekarzem lub fizjoterapeutą.',
              style: TextStyle(color: C.muted, fontSize: 12)),
        ]),
      );
}

/// Krótki opis aktywnych dolegliwości (np. do ustawień).
String injuriesSummary(Profile p) {
  final a = p.activeLimits;
  if (a.isEmpty) return p.noJumping ? 'Bez skoków' : 'Brak — trener dobiera wszystkie ćwiczenia';
  return '${a.join(', ')}${p.noJumping ? ' · bez skoków' : ''}';
}
