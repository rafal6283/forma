import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_settings.dart';
import 'voice.dart';

enum Sfx { tick, go, set, finish, record }

/// Dźwięki i wibracje: odliczanie, start pracy, koniec serii, koniec treningu, rekord.
/// Dźwięki miksują się z muzyką (nie zatrzymują jej).
class Fx {
  Fx._();
  static final instance = Fx._();

  final _players = <Sfx, AudioPlayer>{};
  bool _ready = false;

  Future<void> _init() async {
    if (_ready) return;
    _ready = true;
    try {
      final ctx = AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build();
      for (final s in Sfx.values) {
        final p = AudioPlayer(playerId: 'forma_${s.name}');
        await p.setAudioContext(ctx);
        await p.setReleaseMode(ReleaseMode.stop);
        await p.setPlayerMode(PlayerMode.lowLatency);
        await p.setSource(AssetSource('sounds/${s.name}.wav'));
        _players[s] = p;
      }
    } catch (e) {
      debugPrint('Dźwięki: $e');
    }
  }

  Future<void> play(Sfx s) async {
    final st = AppSettings.instance;
    if (st.haptics) {
      switch (s) {
        case Sfx.tick:
          HapticFeedback.selectionClick();
        case Sfx.go:
          HapticFeedback.mediumImpact();
        case Sfx.set:
          HapticFeedback.mediumImpact();
        case Sfx.finish || Sfx.record:
          HapticFeedback.heavyImpact();
      }
    }
    if (!Voice.instance.beeps) return; // „Sygnały dźwiękowe” w ustawieniach osoby
    await _init();
    final p = _players[s];
    if (p == null) return;
    try {
      await p.stop();
      await p.resume();
    } catch (e) {
      debugPrint('Dźwięki: $e');
    }
  }

  /// Lekkie stuknięcie przy przyciskach (np. licznik powtórzeń).
  void tap() {
    if (AppSettings.instance.haptics) HapticFeedback.lightImpact();
  }
}
