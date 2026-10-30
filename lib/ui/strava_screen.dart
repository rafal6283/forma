import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/store.dart';
import '../core/strava.dart';
import 'theme.dart';
import 'widgets.dart';

/// Połączenie ze Stravą (konto bieżącej osoby + wspólne dane aplikacji API).
class StravaScreen extends StatefulWidget {
  const StravaScreen({super.key});

  @override
  State<StravaScreen> createState() => _StravaScreenState();
}

class _StravaScreenState extends State<StravaScreen> {
  final id = TextEditingController();
  final secret = TextEditingController();
  String? athlete;
  bool hasClient = false;
  bool busy = false;
  bool editClient = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await Strava.instance.client();
    final a = await Strava.instance.athlete();
    if (!mounted) return;
    setState(() {
      hasClient = c != null;
      editClient = c == null;
      if (c != null) id.text = c.$1;
      athlete = a;
    });
  }

  Future<void> _connect() async {
    setState(() => busy = true);
    try {
      if (editClient) {
        if (id.text.trim().isEmpty || secret.text.trim().isEmpty) {
          throw StravaException('Wpisz Client ID i Client Secret.');
        }
        await Strava.instance.setClient(id.text, secret.text);
      }
      final name = await Strava.instance.connect();
      if (mounted) toast(context, 'Połączono: $name');
    } on PlatformException catch (e) {
      if (mounted && e.code != 'CANCELED') toast(context, 'Logowanie przerwane: ${e.message}');
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
    await _load();
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = Store.instance.profile;
    final connected = athlete != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Strava')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(connected ? Icons.check_circle : Icons.link_off, color: connected ? C.good : C.muted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    connected
                        ? 'Połączono${athlete!.isEmpty ? '' : ': $athlete'}'
                        : 'Konto ${p.name.isEmpty ? 'tej osoby' : p.name} nie jest połączone',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              if (connected)
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () async {
                          await Strava.instance.disconnect();
                          await _load();
                        },
                  child: const Text('Rozłącz'),
                )
              else ...[
                if (editClient) ...[
                  TextField(
                    controller: id,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Client ID', isDense: true),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: secret,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Client Secret', isDense: true),
                  ),
                  const SizedBox(height: 12),
                ] else
                  TextButton(
                    onPressed: () => setState(() => editClient = true),
                    child: Text('Aplikacja API: ${id.text} (zmień)'),
                  ),
                FilledButton(
                  onPressed: busy ? null : _connect,
                  child: Text(busy ? 'Łączenie…' : 'Połącz ze Stravą'),
                ),
              ],
            ]),
          ),
        ),
        const SectionTitle('Po treningu'),
        Card(
          child: Column(children: [
            SwitchListTile(
              title: const Text('Wysyłaj automatycznie'),
              value: p.stravaAuto,
              onChanged: (v) async {
                p.stravaAuto = v;
                await Store.instance.save();
                setState(() {});
              },
            ),
            SwitchListTile(
              title: const Text('Uzupełniaj aktywność z zegarka'),
              subtitle: const Text(
                'Gdy zegarek (np. Huawei Health → Strava) już wysłał trening, Forma dopisze nazwę, rodzaj i listę ćwiczeń, '
                'a tętno i kalorie zostaną z zegarka. Bez tej opcji Forma tworzy nową aktywność z tętnem z opaski.',
                style: TextStyle(color: C.muted, fontSize: 12),
              ),
              value: p.stravaMatch,
              onChanged: (v) async {
                p.stravaMatch = v;
                await Store.instance.save();
                setState(() {});
              },
            ),
          ]),
        ),
        const SectionTitle('Jak przygotować'),
        const Text(
          '1. Na strava.com/settings/api utwórz własną aplikację API. Od czerwca 2026 Strava wymaga do tego '
          'subskrypcji na koncie, które zakłada aplikację.\n'
          '2. W polu „Authorization Callback Domain” wpisz: ${Strava.callbackDomain}\n'
          '3. Skopiuj tutaj Client ID i Client Secret (podajesz raz na telefon).\n'
          '4. Każda osoba łączy swoje konto osobno — aplikacja obsłuży do 10 osób bez weryfikacji przez Stravę.\n\n'
          'Bez API: w szczegółach treningu jest przycisk „Plik TCX” — taki plik wgrasz ręcznie na strava.com/upload/select.',
          style: TextStyle(color: C.muted, height: 1.45),
        ),
      ]),
    );
  }
}
