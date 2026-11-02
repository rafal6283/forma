import 'package:flutter/material.dart';

import '../core/hr.dart';
import '../core/store.dart';
import 'theme.dart';
import 'widgets.dart';

/// Inicjały / avatar osoby.
class UserAvatar extends StatelessWidget {
  final String name;
  final double size;
  const UserAvatar(this.name, {super.key, this.size = 36});

  static const _colors = [C.accent, C.good, C.calm, C.warn, Color(0xFFB59BFF), Color(0xFF4FD1C5)];

  @override
  Widget build(BuildContext context) {
    final t = name.trim();
    final letter = t.isEmpty ? '?' : t.characters.first.toUpperCase();
    final c = _colors[t.isEmpty ? 0 : t.codeUnits.fold(0, (a, b) => a + b) % _colors.length];
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: c.withValues(alpha: 0.25),
      child: Text(letter, style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: size * 0.42)),
    );
  }
}

/// Wybór osoby (dane każdej osoby są osobne).
Future<void> showUserSheet(BuildContext context) => showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (c) {
        final s = Store.instance;
        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Kto ćwiczy?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            for (final u in s.users)
              ListTile(
                leading: UserAvatar(u.name.isEmpty ? '?' : u.name),
                title: Text(u.name.isEmpty ? 'Bez imienia' : u.name),
                trailing: u.id == s.userId ? const Icon(Icons.check_circle, color: C.accent) : null,
                onTap: () async {
                  Navigator.pop(c);
                  await HrService.instance.disconnect();
                  await s.switchUser(u.id);
                },
              ),
            ListTile(
              leading: CircleAvatar(backgroundColor: C.surface2, child: Icon(Icons.person_add_alt, color: C.text)),
              title: const Text('Dodaj osobę'),
              onTap: () async {
                Navigator.pop(c);
                final name = await askText(context, 'Imię nowej osoby', '');
                if (name == null || name.isEmpty) return;
                await HrService.instance.disconnect();
                await s.addUser(name);
              },
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Text(
                'Każda osoba ma swój profil, poziom, treningi i pomiary. Health Connect włącz tylko u właściciela telefonu.',
                style: TextStyle(color: C.muted, fontSize: 12),
              ),
            ),
          ]),
        );
      },
    );

/// Pasek z osobą — dotknięcie zmienia osobę.
class UserChip extends StatelessWidget {
  const UserChip({super.key});

  @override
  Widget build(BuildContext context) {
    final s = Store.instance;
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () => showUserSheet(context),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          UserAvatar(s.profile.name, size: 34),
          if (s.users.length > 1) Icon(Icons.expand_more, size: 18, color: C.muted),
        ]),
      ),
    );
  }
}

Future<String?> askText(BuildContext context, String title, String initial, {TextInputType? type}) {
  final ctl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctl,
        keyboardType: type,
        autofocus: true,
        textCapitalization: type == null ? TextCapitalization.words : TextCapitalization.none,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Anuluj')),
        FilledButton(onPressed: () => Navigator.pop(c, ctl.text.trim()), child: const Text('OK')),
      ],
    ),
  );
}

/// Zarządzanie osobami (zmiana imienia, usuwanie).
class UsersScreen extends StatelessWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Store.instance,
        builder: (context, _) {
          final s = Store.instance;
          return Scaffold(
            appBar: AppBar(title: const Text('Osoby')),
            body: ListView(padding: const EdgeInsets.all(16), children: [
              Card(
                child: Column(children: [
                  for (final u in s.users)
                    ListTile(
                      leading: UserAvatar(u.name),
                      title: Text(u.name.isEmpty ? 'Bez imienia' : u.name),
                      subtitle: u.id == s.userId ? const Text('teraz ćwiczy', style: TextStyle(color: C.accent)) : null,
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) async {
                          if (v == 'rename') {
                            final n = await askText(context, 'Imię', u.name);
                            if (n != null && n.isNotEmpty) await s.renameUser(u.id, n);
                          } else if (v == 'delete') {
                            if (await confirm(context, 'Usunąć ${u.name}?',
                                'Treningi, pomiary i ustawienia tej osoby zostaną usunięte z telefonu (kopia na Koofr zostaje).',
                                ok: 'Usuń')) {
                              await s.deleteUser(u.id);
                            }
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'rename', child: Text('Zmień imię')),
                          if (s.users.length > 1) const PopupMenuItem(value: 'delete', child: Text('Usuń')),
                        ],
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final name = await askText(context, 'Imię nowej osoby', '');
                  if (name == null || name.isEmpty) return;
                  await HrService.instance.disconnect();
                  await s.addUser(name);
                  if (context.mounted) Navigator.popUntil(context, (r) => r.isFirst);
                },
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Dodaj osobę'),
              ),
            ]),
          );
        },
      );
}
