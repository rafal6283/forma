import 'package:flutter/material.dart';

import '../core/hr.dart';
import '../core/store.dart';
import 'hrv_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Opaska / zegarek z tętnem przez Bluetooth.
class HrScreen extends StatefulWidget {
  const HrScreen({super.key});

  @override
  State<HrScreen> createState() => _HrScreenState();
}

class _HrScreenState extends State<HrScreen> {
  final hr = HrService.instance;

  @override
  void initState() {
    super.initState();
    final p = Store.instance.profile;
    if (hr.state == HrState.idle && p.hrDeviceId == null) hr.scan();
  }

  @override
  void dispose() {
    hr.stopScan();
    super.dispose();
  }

  Future<void> _connect(HrCandidate c) async {
    final ok = await hr.connect(c.device, name: c.name);
    if (ok) {
      final p = Store.instance.profile;
      p.hrDeviceId = c.device.remoteId.str;
      p.hrDeviceName = c.name;
      await Store.instance.save();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Store.instance.profile;
    return Scaffold(
      appBar: AppBar(title: const Text('Tętno z opaski')),
      body: ListenableBuilder(
        listenable: hr,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(hr.deviceName ?? p.hrDeviceName ?? 'Brak urządzenia',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(
                          switch (hr.state) {
                            HrState.connected => hr.contact
                                ? 'Połączono${hr.battery != null ? ' · bateria ${hr.battery}%' : ''}'
                                : 'Połączono — brak kontaktu ze skórą (zwilż elektrody)',
                            HrState.connecting => 'Łączenie…',
                            HrState.reconnecting => 'Utracono połączenie, ponawiam…',
                            HrState.scanning => 'Szukam urządzeń…',
                            HrState.off => 'Bluetooth wyłączony',
                            HrState.idle => p.hrDeviceId == null ? 'Nie połączono' : 'Zapamiętane, rozłączone',
                          },
                          style: const TextStyle(color: C.muted),
                        ),
                      ]),
                    ),
                    const HrBadge(large: true),
                  ]),
                  if (hr.error != null) ...[
                    const SizedBox(height: 10),
                    Text(hr.error!, style: const TextStyle(color: C.bad)),
                  ],
                  const SizedBox(height: 14),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    if (!hr.connected && p.hrDeviceId != null)
                      FilledButton.icon(
                        onPressed: hr.state == HrState.connecting ? null : () => hr.connectSaved(p.hrDeviceId!, p.hrDeviceName),
                        icon: const Icon(Icons.bluetooth_connected),
                        label: const Text('Połącz'),
                      ),
                    if (hr.connected || hr.state == HrState.reconnecting)
                      OutlinedButton(onPressed: hr.disconnect, child: const Text('Rozłącz')),
                    if (hr.connected)
                      OutlinedButton.icon(
                        onPressed: () =>
                            Navigator.push(context, MaterialPageRoute(builder: (_) => const HrvScreen())),
                        icon: const Icon(Icons.monitor_heart_outlined),
                        label: const Text('Pomiar HRV'),
                      ),
                    if (p.hrDeviceId != null)
                      TextButton(
                        onPressed: () async {
                          await hr.disconnect();
                          p.hrDeviceId = null;
                          p.hrDeviceName = null;
                          await Store.instance.save();
                        },
                        child: const Text('Zapomnij'),
                      ),
                  ]),
                ]),
              ),
            ),
            SectionTitle(
              'Urządzenia w pobliżu',
              trailing: hr.state == HrState.scanning
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : TextButton.icon(onPressed: hr.scan, icon: const Icon(Icons.refresh, size: 18), label: const Text('Szukaj')),
            ),
            ValueListenableBuilder<List<HrCandidate>>(
              valueListenable: hr.candidates,
              builder: (context, list, _) => list.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        hr.state == HrState.scanning
                            ? 'Załóż opaskę (zwilż elektrody) albo włącz w zegarku udostępnianie tętna.'
                            : 'Nic nie znaleziono. Dotknij „Szukaj”.',
                        style: const TextStyle(color: C.muted),
                      ),
                    )
                  : Card(
                      child: Column(children: [
                        for (final c in list)
                          ListTile(
                            leading: const Icon(Icons.favorite_border, color: C.accent),
                            title: Text(c.name),
                            subtitle: Text('Sygnał ${c.rssi} dBm', style: const TextStyle(color: C.muted)),
                            trailing: hr.state == HrState.connecting && hr.deviceName == c.name
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.chevron_right),
                            onTap: () => _connect(c),
                          ),
                      ]),
                    ),
            ),
            const SectionTitle('Co działa'),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'Opaski na klatkę i ramię z Bluetooth: Polar H9/H10/Verity Sense, Garmin HRM, Wahoo, Coospo, Magene i inne.\n\n'
                'Zegarki — tylko w trybie udostępniania tętna: Garmin („Transmisja tętna”), Polar („Udostępnij tętno”), '
                'Suunto, Coros, nowsze Amazfit i Xiaomi. Starsze zegarki Huawei (np. Watch GT 2) zwykle nie mają tej funkcji — '
                'ich tętno trafi do Formy po treningu przez Health Connect.\n\n'
                'Opaski z odstępami RR (np. Polar H10) pozwalają też zmierzyć poranne HRV, które poprawia ocenę gotowości.',
                style: TextStyle(color: C.muted, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
