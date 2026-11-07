import 'package:flutter/material.dart';
import 'package:koofr_backup_ui/koofr_backup_ui.dart';

import '../core/catalog.dart';
import '../core/family.dart';
import 'theme.dart';
import 'widgets.dart';

/// Rywalizacja z rodziną: tabela tygodnia, serie, poziomy i wspólne wyzwania.
class FamilyScreen extends StatefulWidget {
  const FamilyScreen({super.key});

  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

class _Person {
  final Member m;
  final ShareLink? out, inn; // ja → ona, ona → ja
  final FamilyCard? card;
  _Person(this.m, this.out, this.inn, this.card);

  bool get iAgreed => (out?.ownerAgreed ?? false) && (inn?.viewerAgreed ?? false);
  bool get theyAgreed => (out?.viewerAgreed ?? false) || (inn?.ownerAgreed ?? false);
  bool get active => inn?.active == true;
}

class _FamilyScreenState extends State<FamilyScreen> {
  final f = Family.instance;
  bool loading = true;
  String? error;
  String? meId;
  List<_Person> people = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final s = f.sync;
      if (s == null || !s.ready) {
        setState(() => loading = false);
        return;
      }
      meId = s.userId;
      await f.publish();
      final members = (await s.members()).where((m) => m.id != meId).toList();
      final links = await s.links();
      final out = <_Person>[];
      for (final m in members) {
        ShareLink? find(String o, String v) {
          for (final l in links) {
            if (l.owner == o && l.viewer == v) return l;
          }
          return null;
        }

        final inn = find(m.id, meId!);
        out.add(_Person(m, find(meId!, m.id), inn, inn?.active == true ? await f.fetch(m.id) : null));
      }
      if (!mounted) return;
      setState(() {
        people = out;
        loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
          loading = false;
        });
      }
    }
  }

  Future<void> _act(Future<void> Function() a) async {
    setState(() => loading = true);
    try {
      await a();
    } catch (e) {
      if (mounted) toast(context, 'Nie udało się: $e');
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final mine = FamilyCard.mine(name: 'Ty');
    final board = [mine, for (final p in people) if (p.card != null) p.card!]
      ..sort((a, b) => b.weekMinutes.compareTo(a.weekMinutes));
    return Scaffold(
      appBar: AppBar(title: const Text('Rodzina'), actions: [
        IconButton(onPressed: loading ? null : _load, icon: const Icon(Icons.refresh)),
      ]),
      body: !f.ready
          ? ListView(padding: const EdgeInsets.all(24), children: [
              Text(
                'Rywalizacja z rodziną działa przez wspólne konto Koofr — to samo, na które idzie kopia zapasowa. '
                'Każdy trenuje na swoim telefonie, a wyniki (tylko liczby: dni, minuty, seria, poziom, wyzwania) '
                'wymieniacie za zgodą obu stron, zaszyfrowane.',
                style: TextStyle(color: C.muted, height: 1.4),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => const KoofrBackupScreen()));
                  await _load();
                },
                icon: const Icon(Icons.cloud_outlined),
                label: const Text('Połącz konto Koofr'),
              ),
            ])
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
                if (loading) const LinearProgressIndicator(),
                if (error != null) Text(error!, style: const TextStyle(color: C.bad)),
                const SectionTitle('Ten tydzień'),
                Card(
                  child: Column(children: [
                    for (var i = 0; i < board.length; i++)
                      ListTile(
                        leading: CircleAvatar(
                          backgroundColor: (i == 0 ? C.warn : C.surface2).withValues(alpha: i == 0 ? 0.3 : 1),
                          child: Text('${i + 1}', style: TextStyle(fontWeight: FontWeight.w800, color: i == 0 ? C.warn : C.text)),
                        ),
                        title: Text(board[i].name.isEmpty ? '—' : board[i].name,
                            style: TextStyle(fontWeight: identical(board[i], mine) ? FontWeight.w800 : FontWeight.w600)),
                        subtitle: Text(
                          '${board[i].weekDays} dni · 🔥 ${board[i].streak} · poziom ${board[i].level}',
                          style: TextStyle(color: C.muted),
                        ),
                        trailing: Text('${board[i].weekMinutes} min', style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                  ]),
                ),
                if (_sharedChallenges(mine).isNotEmpty) ...[
                  const SectionTitle('Wspólne wyzwania'),
                  for (final c in _sharedChallenges(mine))
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(c.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 8),
                          for (final card in board)
                            if (card.challenges.containsKey(c.id))
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 3),
                                child: Row(children: [
                                  SizedBox(width: 90, child: Text(card.name, overflow: TextOverflow.ellipsis)),
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: card.challenges[c.id]! / c.days,
                                        minHeight: 8,
                                        backgroundColor: C.surface2,
                                        color: C.accent,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                      width: 56, child: Text('${card.challenges[c.id]}/${c.days}', textAlign: TextAlign.right)),
                                ]),
                              ),
                        ]),
                      ),
                    ),
                ],
                const SectionTitle('Osoby na koncie'),
                if (people.isEmpty && !loading)
                  Text('Na koncie Koofr nie ma jeszcze innych osób. Dodajcie się w Formie na swoich telefonach '
                      '(Ustawienia → Kopia na Koofr) tym samym kontem rodzinnym.',
                      style: TextStyle(color: C.muted)),
                for (final p in people)
                  Card(
                    child: ListTile(
                      title: Text(p.m.name),
                      subtitle: Text(
                        p.active && p.iAgreed
                            ? (p.card == null ? 'Połączeni — czekam na pierwsze wyniki' : 'Połączeni · wyniki z ${fmtDate(p.card!.at)}')
                            : p.iAgreed
                                ? 'Zaproszenie wysłane — czeka na zgodę'
                                : p.theyAgreed
                                    ? 'Zaprasza Cię do rywalizacji'
                                    : 'Nie rywalizujecie',
                        style: TextStyle(color: p.theyAgreed && !p.iAgreed ? C.accent : C.muted),
                      ),
                      trailing: p.iAgreed
                          ? TextButton(onPressed: () => _act(() => f.disconnect(p.m.id)), child: const Text('Zakończ'))
                          : FilledButton.tonal(
                              onPressed: () => _act(() => f.connect(p.m.id)),
                              child: Text(p.theyAgreed ? 'Przyjmij' : 'Zaproś'),
                            ),
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  'Wymieniane są tylko liczby z tabeli i postęp wyzwań — bez tętna, HRV, pomiarów ciała i samopoczucia. '
                  'Wyniki odświeżają się przy otwarciu tego ekranu i po każdym treningu.',
                  style: TextStyle(color: C.muted, fontSize: 12),
                ),
              ]),
            ),
    );
  }

  List<ChallengeDef> _sharedChallenges(FamilyCard mine) {
    final others = people.where((p) => p.card != null).map((p) => p.card!).toList();
    return [
      for (final c in challengeDefs)
        if (mine.challenges.containsKey(c.id) && others.any((o) => o.challenges.containsKey(c.id))) c,
    ];
  }
}
