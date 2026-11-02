import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/store.dart';
import 'theme.dart';

/// Pierwsze uruchomienie: kilka pytań, żeby trener wiedział, od czego zacząć.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onDone;
  const OnboardingScreen({super.key, required this.onDone});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final p = Store.instance.profile;
  final page = PageController();
  int i = 0;
  late final name = TextEditingController(text: p.name);
  late final weight = TextEditingController(text: p.weightKg.toStringAsFixed(0));
  late final height = TextEditingController(text: '${p.heightCm}');
  late final year = TextEditingController(text: '${p.birthYear}');

  static const levels = [
    (1.0, 'Dopiero zaczynam', 'Mało się ruszam, kilka pompek to wyzwanie'),
    (2.0, 'Ćwiczę czasem', 'Ruszam się, ale bez regularnych treningów'),
    (3.0, 'Ćwiczę regularnie', '2–3 treningi w tygodniu od kilku miesięcy'),
    (4.0, 'Zaawansowany', 'Pompki, przysiady i deska to dla mnie codzienność'),
  ];

  void _next() {
    if (i == 1) {
      p.weightKg = double.tryParse(weight.text.replaceAll(',', '.')) ?? p.weightKg;
      p.heightCm = int.tryParse(height.text) ?? p.heightCm;
      final y = int.tryParse(year.text);
      if (y != null && y > 1920 && y < DateTime.now().year - 8) p.birthYear = y;
    }
    if (i == 0) p.name = name.text.trim();
    if (i == _pages - 1) {
      p.onboarded = true;
      Store.instance.save();
      widget.onDone();
      return;
    }
    page.nextPage(duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
  }

  static const _pages = 5;

  Widget _title(String t, [String? sub]) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, height: 1.15)),
          if (sub != null) ...[
            const SizedBox(height: 8),
            Text(sub, style: TextStyle(color: C.muted, fontSize: 15, height: 1.35)),
          ],
        ]),
      );

  InputDecoration _dec(String label, [String? suffix]) => InputDecoration(
        labelText: label,
        suffixText: suffix,
        filled: true,
        fillColor: C.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      );

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      ListView(padding: const EdgeInsets.all(24), children: [
        const SizedBox(height: 24),
        const Icon(Icons.bolt, size: 56, color: C.accent),
        const SizedBox(height: 16),
        _title('Cześć, tu Forma', 'Trener personalny w telefonie. Codziennie sprawdza, jak się czujesz, i układa trening na dziś.'),
        TextField(controller: name, decoration: _dec('Jak masz na imię?'), textCapitalization: TextCapitalization.words),
      ]),
      ListView(padding: const EdgeInsets.all(24), children: [
        _title('Kilka liczb', 'Do kalorii i stref tętna. Zostają na telefonie.'),
        SegmentedButton<String>(
          segments: const [ButtonSegment(value: 'k', label: Text('Kobieta')), ButtonSegment(value: 'm', label: Text('Mężczyzna'))],
          selected: {p.sex},
          onSelectionChanged: (v) => setState(() => p.sex = v.first),
        ),
        const SizedBox(height: 14),
        TextField(controller: year, keyboardType: TextInputType.number, decoration: _dec('Rok urodzenia')),
        const SizedBox(height: 12),
        TextField(controller: weight, keyboardType: TextInputType.number, decoration: _dec('Waga', 'kg')),
        const SizedBox(height: 12),
        TextField(controller: height, keyboardType: TextInputType.number, decoration: _dec('Wzrost', 'cm')),
      ]),
      ListView(padding: const EdgeInsets.all(24), children: [
        _title('Twój cel'),
        for (final g in Goal.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _Option(
              title: goalLabel[g]!,
              selected: p.goal == g,
              onTap: () => setState(() => p.goal = g),
            ),
          ),
      ]),
      ListView(padding: const EdgeInsets.all(24), children: [
        _title('Jak wygląda Twoja forma?', 'Trener zacznie od tego poziomu i sam go dopasuje po pierwszych treningach.'),
        for (final l in levels)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _Option(
              title: l.$2,
              subtitle: l.$3,
              selected: p.level.round() == l.$1.round(),
              onTap: () => setState(() => p.level = l.$1),
            ),
          ),
      ]),
      ListView(padding: const EdgeInsets.all(24), children: [
        _title('Warunki', 'Ćwiczenia są głównie bez sprzętu — zaznacz, co masz, a trener chętnie z tego skorzysta.'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in equipmentLabel.entries)
            FilterChip(
              label: Text(e.value),
              selected: p.equipment.contains(e.key),
              onSelected: (v) => setState(() => v ? p.equipment.add(e.key) : p.equipment.remove(e.key)),
            ),
        ]),
        const SizedBox(height: 20),
        const Text('Oszczędzaj', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final l in limitLabels)
            FilterChip(
              label: Text(l),
              selected: p.limits.contains(l),
              onSelected: (v) => setState(() => v ? p.limits.add(l) : p.limits.remove(l)),
            ),
        ]),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Bez skoków (cicho dla sąsiadów)'),
          value: p.noJumping,
          onChanged: (v) => setState(() => p.noJumping = v),
        ),
        const SizedBox(height: 8),
        Text('Trening: ${p.minutes} min', style: const TextStyle(fontWeight: FontWeight.w700)),
        Slider(
          value: p.minutes.toDouble(),
          min: 10,
          max: 60,
          divisions: 10,
          onChanged: (v) => setState(() => p.minutes = v.round()),
        ),
        Text('Treningi w tygodniu: ${p.daysPerWeek}', style: const TextStyle(fontWeight: FontWeight.w700)),
        Slider(
          value: p.daysPerWeek.toDouble(),
          min: 1,
          max: 7,
          divisions: 6,
          onChanged: (v) => setState(() => p.daysPerWeek = v.round()),
        ),
      ]),
    ];
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Row(children: [
              for (var k = 0; k < _pages; k++)
                Expanded(
                  child: Container(
                    height: 4,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: k <= i ? C.accent : C.surface2,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
            ]),
          ),
          Expanded(
            child: PageView(
              controller: page,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (v) => setState(() => i = v),
              children: pages,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Row(children: [
              if (i > 0)
                TextButton(
                  onPressed: () => page.previousPage(duration: const Duration(milliseconds: 260), curve: Curves.easeOut),
                  child: const Text('Wstecz'),
                ),
              const Spacer(),
              FilledButton(
                onPressed: _next,
                style: FilledButton.styleFrom(minimumSize: const Size(140, 52)),
                child: Text(i == _pages - 1 ? 'Zaczynamy' : 'Dalej'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
  const _Option({required this.title, required this.selected, required this.onTap, this.subtitle});

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? C.accent.withValues(alpha: 0.15) : C.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: selected ? C.accent : Colors.transparent, width: 1.5),
            ),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: TextStyle(color: C.muted)),
                  ],
                ]),
              ),
              if (selected) const Icon(Icons.check_circle, color: C.accent),
            ]),
          ),
        ),
      );
}
