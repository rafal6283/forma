import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

enum HrState { off, idle, scanning, connecting, connected, reconnecting }

/// Urządzenie znalezione podczas skanowania.
class HrCandidate {
  final BluetoothDevice device;
  final String name;
  final int rssi;
  HrCandidate(this.device, this.name, this.rssi);
}

/// Tętno z opasek i zegarków przez standardową usługę Heart Rate (BLE 0x180D):
/// Polar, Garmin HRM, Wahoo, Coospo, Magene, a także zegarki w trybie „udostępniania tętna”.
class HrService extends ChangeNotifier {
  HrService._();
  static final instance = HrService._();

  static final _hrService = Guid('180D');
  static bool _is(Guid g, String short) {
    final s = g.str128.toLowerCase();
    return s.startsWith('0000$short-') || g.toString().toLowerCase() == short;
  }

  HrState state = HrState.idle;
  int? bpm;
  int? battery;
  String? deviceName;
  String? error;
  DateTime? lastBeat;
  bool contact = true;

  /// Odstępy RR (ms) — do pomiaru HRV.
  final rr = StreamController<double>.broadcast();

  final candidates = ValueNotifier<List<HrCandidate>>([]);

  BluetoothDevice? _device;
  StreamSubscription<List<int>>? _valueSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  StreamSubscription<List<ScanResult>>? _scanSub;
  bool _wanted = false;
  Timer? _retry;

  bool get connected => state == HrState.connected;

  /// Odczyt starszy niż 5 s uznajemy za nieaktualny.
  int? get freshBpm => lastBeat != null && DateTime.now().difference(lastBeat!).inSeconds < 5 ? bpm : null;

  Future<bool> _ensureOn() async {
    try {
      if (!await FlutterBluePlus.isSupported) {
        error = 'Ten telefon nie obsługuje Bluetooth LE.';
        return false;
      }
      var st = FlutterBluePlus.adapterStateNow;
      if (st == BluetoothAdapterState.unknown) {
        st = await FlutterBluePlus.adapterState.where((s) => s != BluetoothAdapterState.unknown).first.timeout(
              const Duration(seconds: 3),
              onTimeout: () => BluetoothAdapterState.unknown,
            );
      }
      if (st != BluetoothAdapterState.on) {
        if (Platform.isAndroid) {
          await FlutterBluePlus.turnOn();
        } else {
          error = 'Włącz Bluetooth w ustawieniach telefonu.';
          state = HrState.off;
          notifyListeners();
          return false;
        }
      }
      return true;
    } catch (e) {
      error = 'Bluetooth: $e';
      notifyListeners();
      return false;
    }
  }

  Future<void> scan() async {
    if (!await _ensureOn()) return;
    error = null;
    candidates.value = [];
    state = HrState.scanning;
    notifyListeners();
    await _scanSub?.cancel();
    _scanSub = FlutterBluePlus.onScanResults.listen((list) {
      final seen = <String, HrCandidate>{for (final c in candidates.value) c.device.remoteId.str: c};
      for (final r in list) {
        final name = r.advertisementData.advName.isNotEmpty ? r.advertisementData.advName : r.device.platformName;
        seen[r.device.remoteId.str] = HrCandidate(r.device, name.isEmpty ? 'Urządzenie ${r.device.remoteId.str}' : name, r.rssi);
      }
      candidates.value = seen.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi));
    });
    try {
      await FlutterBluePlus.startScan(withServices: [_hrService], timeout: const Duration(seconds: 15));
      await FlutterBluePlus.isScanning.where((s) => !s).first;
    } catch (e) {
      error = 'Skanowanie: $e';
    }
    if (state == HrState.scanning) state = _device != null && connected ? HrState.connected : HrState.idle;
    notifyListeners();
  }

  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
  }

  /// Łączy z urządzeniem; [remember] = po sukcesie zapisz jako domyślne (robi to wywołujący).
  Future<bool> connect(BluetoothDevice d, {String? name}) async {
    if (!await _ensureOn()) return false;
    await stopScan();
    await _teardown();
    _wanted = true;
    _device = d;
    deviceName = name ?? (d.platformName.isNotEmpty ? d.platformName : deviceName);
    state = HrState.connecting;
    error = null;
    notifyListeners();
    try {
      await d.connect(license: License.nonprofit, timeout: const Duration(seconds: 15), mtu: null);
      _connSub = d.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected && _wanted) {
          state = HrState.reconnecting;
          bpm = null;
          notifyListeners();
          _scheduleRetry();
        }
      });
      final services = await d.discoverServices();
      BluetoothCharacteristic? hrChar, batChar;
      for (final s in services) {
        for (final c in s.characteristics) {
          if (_is(c.uuid, '2a37')) hrChar = c;
          if (_is(c.uuid, '2a19')) batChar = c;
        }
      }
      if (hrChar == null) {
        throw Exception('Urządzenie nie udostępnia tętna (brak usługi Heart Rate).');
      }
      _valueSub = hrChar.onValueReceived.listen(_onHr);
      d.cancelWhenDisconnected(_valueSub!);
      await hrChar.setNotifyValue(true);
      if (batChar != null) {
        try {
          final v = await batChar.read();
          if (v.isNotEmpty) battery = v.first;
        } catch (_) {}
      }
      state = HrState.connected;
      notifyListeners();
      return true;
    } catch (e) {
      error = '$e'.replaceFirst('Exception: ', '');
      state = HrState.idle;
      _wanted = false;
      notifyListeners();
      try {
        await d.disconnect();
      } catch (_) {}
      return false;
    }
  }

  /// Połączenie z zapamiętanym urządzeniem (bez skanowania).
  Future<bool> connectSaved(String id, String? name) => connect(BluetoothDevice.fromId(id), name: name);

  void _scheduleRetry() {
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 4), () async {
      final d = _device;
      if (!_wanted || d == null || connected) return;
      await _valueSub?.cancel();
      await _connSub?.cancel();
      final ok = await connect(d, name: deviceName);
      if (!ok && _wanted) {
        _wanted = true;
        state = HrState.reconnecting;
        notifyListeners();
        _scheduleRetry();
      }
    });
  }

  void _onHr(List<int> v) {
    if (v.isEmpty) return;
    final flags = v[0];
    final wide = flags & 0x01 != 0;
    var i = 1;
    int value;
    if (wide) {
      if (v.length < 3) return;
      value = v[1] | (v[2] << 8);
      i = 3;
    } else {
      if (v.length < 2) return;
      value = v[1];
      i = 2;
    }
    // bit 1–2: styk z ciałem (obsługiwany i wykryty)
    if (flags & 0x04 != 0) contact = flags & 0x02 != 0;
    if (flags & 0x08 != 0) i += 2; // zużyta energia
    if (flags & 0x10 != 0) {
      for (; i + 1 < v.length; i += 2) {
        final raw = v[i] | (v[i + 1] << 8);
        rr.add(raw / 1024 * 1000);
      }
    }
    if (value > 0) {
      bpm = value;
      lastBeat = DateTime.now();
      notifyListeners();
    }
  }

  Future<void> _teardown() async {
    _retry?.cancel();
    await _valueSub?.cancel();
    await _connSub?.cancel();
    _valueSub = null;
    _connSub = null;
  }

  Future<void> disconnect() async {
    _wanted = false;
    await _teardown();
    try {
      await _device?.disconnect();
    } catch (_) {}
    _device = null;
    bpm = null;
    battery = null;
    state = HrState.idle;
    notifyListeners();
  }
}
