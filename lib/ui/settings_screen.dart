import 'dart:io';

import 'package:flutter/material.dart';
import 'package:koofr_backup_ui/koofr_backup_ui.dart';

import '../core/coach.dart';
import '../core/health_sync.dart';
import '../core/models.dart';
import '../core/store.dart';
import '../core/voice.dart';
import 'hr_screen.dart';
import 'strava_screen.dart';
import 'users.dart';
import 'theme.dart';
import 'widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final store = Store.instance;
  Profile get p => store.profile;

  Future<void> _save() async {
    setState(() {});
    Voice.instance.enabled = p.voice;
    Voice.instance.beeps = p.beeps;
    await store.save();
  }

  Future<String?> _ask(String title, String initial, {TextInputType? type}) {
    final ctl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: TextField(controller: ctl, keyboardType: type, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Anuluj')),
          FilledButton(onPressed: () => Navigator.pop(c, ctl.text.trim()), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _toggleHealth(bool v) async {
    if (!v) {
      p.healthConnect = false;
      await _save();
      return;
    }
    final hs = HealthSync.instance;
    if (!await hs.available()) {
      if (!mounted) return;
      final install = await confirm(context, 'Brak Health Connect',
          'Zainstaluj aplikację Health Connect ze Sklepu Play, potem włącz tę opcję ponownie.',
          ok: 'Zainstaluj');
      if (install) await hs.installHealthConnect();
      return;
    }
    final ok = await hs.authorize();
    p.healthConnect = ok;
    await _save();
    if (ok) {
      await refreshHealth();
      final w = store.health.weightKg;
      if (w != null) {
        p.weightKg = (w * 10).round() / 10;
        await _save();
      }
    } else if (mounted) {
      toast(context, hs.lastError ?? 'Brak zgody na dostęp do danych zdrowia');
    }
  }

  @override
  Widget build(BuildContext context) {
    final healthName = Platform.isIOS ? 'Zdrowie (Apple)' : 'Health Connect';
    return Scaffold(
      appBar: AppBar(title: const Text('Ustawienia')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 40), children: [
        const SectionTitle('Ty'),
        Card(
          child: Column(children: [
            ListTile(
              title: const Text('Imię'),
              trailing: Text(p.name.isEmpty ? '—' : p.name),
              onTap: () async {
                final v = await _ask('Imię', p.name);
                if (v != null) {
                  p.name = v;
                  await _save();
                }
              },
            ),
            ListTile(
              title: const Text('Płeć'),
              trailing: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [ButtonSegment(value: 'k', label: Text('K')), ButtonSegment(value: 'm', label: Text('M'))],
                selected: {p.sex},
                onSelectionChanged: (v) {
                  p.sex = v.first;
                  _save();
                },
              ),
            ),
            ListTile(
              title: const Text('Rok urodzenia'),
              trailing: Text('${p.birthYear}'),
              onTap: () async {
                final v = int.tryParse(await _ask('Rok urodzenia', '${p.birthYear}', type: TextInputType.number) ?? '');
                if (v != null && v > 1920 && v < DateTime.now().year - 8) {
                  p.birthYear = v;
                  await _save();
                }
              },
            ),
            ListTile(
              title: const Text('Waga'),
              trailing: Text('${p.weightKg.toStringAsFixed(1).replaceAll('.', ',')} kg'),
              onTap: () async {
                final v = double.tryParse(
                    (await _ask('Waga (kg)', '${p.weightKg}', type: TextInputType.number) ?? '').replaceAll(',', '.'));
                if (v != null && v > 25 && v < 300) {
                  p.weightKg = v;
                  await _save();
                }
              },
            ),
            ListTile(
              title: const Text('Wzrost'),
              trailing: Text('${p.heightCm} cm'),
              onTap: () async {
                final v = int.tryParse(await _ask('Wzrost (cm)', '${p.heightCm}', type: TextInputType.number) ?? '');
                if (v != null && v > 100 && v < 230) {
                  p.heightCm = v;
                  await _save();
                }
              },
            ),
          ]),
        ),
        const SectionTitle('Trening'),
        Card(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ListTile(
              title: const Text('Cel'),
              subtitle: Text(goalLabel[p.goal]!, style: const TextStyle(color: C.accent)),
              onTap: () async {
                final g = await showModalBottomSheet<Goal>(
                  context: context,
                  showDragHandle: true,
                  builder: (c) => SafeArea(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      for (final g in Goal.values)
                        ListTile(
                          title: Text(goalLabel[g]!),
                          trailing: g == p.goal ? const Icon(Icons.check, color: C.accent) : null,
                          onTap: () => Navigator.pop(c, g),
                        ),
                    ]),
                  ),
                );
                if (g != null) {
                  p.goal = g;
                  await _save();
                }
              },
            ),
            _SliderTile(
              label: 'Poziom',
              value: p.level,
              min: 1,
              max: 5,
              divisions: 40,
              text: '${p.level.toStringAsFixed(1).replaceAll('.', ',')} — ${_levelName(p.level)}',
              hint: 'Trener zmienia go sam po każdym treningu, według Twoich ocen.',
              onChanged: (v) => setState(() => p.level = (v * 10).round() / 10),
              onEnd: (_) => _save(),
            ),
            _SliderTile(
              label: 'Czas treningu',
              value: p.minutes.toDouble(),
              min: 10,
              max: 60,
              divisions: 10,
              text: '${p.minutes} min',
              onChanged: (v) => setState(() => p.minutes = v.round()),
              onEnd: (_) => _save(),
            ),
            _SliderTile(
              label: 'Treningi w tygodniu',
              value: p.daysPerWeek.toDouble(),
              min: 1,
              max: 7,
              divisions: 6,
              text: '${p.daysPerWeek}',
              onChanged: (v) => setState(() => p.daysPerWeek = v.round()),
              onEnd: (_) => _save(),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Text('Sprzęt w domu', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final e in equipmentLabel.entries)
                  FilterChip(
                    label: Text(e.value),
                    selected: p.equipment.contains(e.key),
                    onSelected: (v) {
                      v ? p.equipment.add(e.key) : p.equipment.remove(e.key);
                      _save();
                    },
                  ),
              ]),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 6),
              child: Text('Oszczędzaj', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final l in limitLabels)
                  FilterChip(
                    label: Text(l),
                    selected: p.limits.contains(l),
                    onSelected: (v) {
                      v ? p.limits.add(l) : p.limits.remove(l);
                      _save();
                    },
                  ),
              ]),
            ),
            SwitchListTile(
              title: const Text('Bez skoków'),
              subtitle: const Text('Cicho dla sąsiadów', style: TextStyle(color: C.muted)),
              value: p.noJumping,
              onChanged: (v) {
                p.noJumping = v;
                _save();
              },
            ),
          ]),
        ),
        const SectionTitle('Tętno i zdrowie'),
        Card(
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.favorite_border),
              title: const Text('Opaska / zegarek'),
              subtitle: Text(p.hrDeviceName ?? 'Nie połączono', style: const TextStyle(color: C.muted)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const HrScreen()));
                setState(() {});
              },
            ),
            ListTile(
              title: const Text('Tętno maksymalne'),
              subtitle: Text(p.maxHrOverride == null ? 'Z wieku: ${p.maxHr}' : 'Ustawione ręcznie',
                  style: const TextStyle(color: C.muted)),
              trailing: Text('${p.maxHr}'),
              onTap: () async {
                final v = await _ask('Tętno maksymalne (puste = z wieku)', p.maxHrOverride?.toString() ?? '',
                    type: TextInputType.number);
                if (v == null) return;
                final n = int.tryParse(v);
                p.maxHrOverride = n != null && n > 120 && n < 230 ? n : null;
                await _save();
              },
            ),
            SwitchListTile(
              secondary: const Icon(Icons.health_and_safety_outlined),
              title: Text(healthName),
              subtitle: const Text('Zapis treningów; odczyt snu, tętna, HRV i wagi', style: TextStyle(color: C.muted)),
              value: p.healthConnect,
              onChanged: _toggleHealth,
            ),
          ]),
        ),
        const SectionTitle('Podczas treningu'),
        Card(
          child: Column(children: [
            SwitchListTile(
              title: const Text('Komunikaty głosowe'),
              value: p.voice,
              onChanged: (v) {
                p.voice = v;
                _save();
              },
            ),
            SwitchListTile(
              title: const Text('Sygnały i wibracje'),
              subtitle: const Text('Odliczanie ostatnich sekund', style: TextStyle(color: C.muted)),
              value: p.beeps,
              onChanged: (v) {
                p.beeps = v;
                _save();
              },
            ),
          ]),
        ),
        const SectionTitle('Strava'),
        Card(
          child: ListTile(
            leading: const Icon(Icons.directions_run),
            title: const Text('Strava'),
            subtitle: const Text('Uzupełnianie aktywności z zegarka lub wysyłka treningu', style: TextStyle(color: C.muted)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StravaScreen())),
          ),
        ),
        const SectionTitle('Dane'),
        Card(
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.group_outlined),
              title: const Text('Osoby'),
              subtitle: Text('${store.users.length} · teraz: ${p.name.isEmpty ? '—' : p.name}', style: const TextStyle(color: C.muted)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UsersScreen())),
            ),
            const KoofrBackupTile(),
          ]),
        ),
        const SizedBox(height: 24),
        const Center(child: Text('Forma 1.2 · trener działa na telefonie, bez chmury', style: TextStyle(color: C.muted, fontSize: 12))),
      ]),
    );
  }

  static String _levelName(double l) => l < 1.8
      ? 'początkujący'
      : l < 2.6
          ? 'podstawowy'
          : l < 3.4
              ? 'średni'
              : l < 4.2
                  ? 'zaawansowany'
                  : 'bardzo zaawansowany';
}

class _SliderTile extends StatelessWidget {
  final String label, text;
  final String? hint;
  final double value, min, max;
  final int divisions;
  final ValueChanged<double> onChanged, onEnd;

  const _SliderTile({
    required this.label,
    required this.text,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    required this.onEnd,
    this.hint,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(label)),
            Text(text, style: const TextStyle(color: C.accent, fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
          ]),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
            onChangeEnd: onEnd,
          ),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 8),
              child: Text(hint!, style: const TextStyle(color: C.muted, fontSize: 12)),
            ),
        ]),
      );
}
