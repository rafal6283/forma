import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Komunikaty głosowe trenera (syntezator mowy telefonu, po polsku).
class Voice {
  Voice._();
  static final instance = Voice._();

  final _tts = FlutterTts();
  bool enabled = true;
  bool beeps = true;
  bool _ready = false;

  /// Trener właśnie mówi — rozpoznawanie mowy w tym czasie milknie, żeby nie słyszało samego siebie.
  final speaking = ValueNotifier<bool>(false);

  Future<void> init() async {
    if (_ready) return;
    try {
      _tts.setStartHandler(() => speaking.value = true);
      _tts.setCompletionHandler(() => speaking.value = false);
      _tts.setCancelHandler(() => speaking.value = false);
      _tts.setErrorHandler((_) => speaking.value = false);
      await _tts.setLanguage('pl-PL');
      await _tts.setSpeechRate(0.5);
      await _tts.awaitSpeakCompletion(false);
      // nie przerywaj muzyki na stałe — tylko przycisz na czas komunikatu (iOS)
      await _tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [IosTextToSpeechAudioCategoryOptions.duckOthers, IosTextToSpeechAudioCategoryOptions.mixWithOthers],
      );
      _ready = true;
    } catch (e) {
      debugPrint('TTS: $e');
    }
  }

  Future<void> say(String text) async {
    if (!enabled) return;
    await init();
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (e) {
      debugPrint('TTS: $e');
    }
  }

  /// Krótki sygnał w ostatnich sekundach.
  void tick() {
    if (!beeps) return;
    SystemSound.play(SystemSoundType.click);
    HapticFeedback.lightImpact();
  }

  void go() {
    if (!beeps) return;
    HapticFeedback.mediumImpact();
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
