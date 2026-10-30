import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'voice.dart';

enum VoiceCmd { next, pause, resume, prev, done, harder, easier, pain, remaining, setReps }

/// Sterowanie głosem podczas treningu (rozpoznawanie mowy w telefonie, po polsku).
///
/// Słucha w pętli krótkimi sesjami; milknie, gdy mówi trener, żeby nie reagować na własne komunikaty.
class VoiceCommands extends ChangeNotifier {
  VoiceCommands._();
  static final instance = VoiceCommands._();

  final _stt = SpeechToText();
  bool available = false;
  bool active = false;
  bool listening = false;
  String lastHeard = '';
  String? error;
  void Function(VoiceCmd cmd, int? value)? onCommand;
  bool _handledThisUtterance = false;
  Timer? _restart;

  static const _words = <VoiceCmd, List<String>>{
    VoiceCmd.next: ['dalej', 'następne', 'następny', 'pomiń', 'pomin', 'next'],
    VoiceCmd.pause: ['pauza', 'stop', 'zatrzymaj', 'czekaj'],
    VoiceCmd.resume: ['wznów', 'wznow', 'start', 'kontynuuj', 'jedziemy', 'graj'],
    VoiceCmd.prev: ['wstecz', 'cofnij', 'poprzednie', 'jeszcze raz'],
    VoiceCmd.done: ['gotowe', 'zrobione', 'koniec serii', 'zrobiłem', 'zrobiłam', 'seria'],
    VoiceCmd.harder: ['za trudne', 'za ciężko', 'za ciezko', 'za trudno', 'ciężko', 'nie daję rady'],
    VoiceCmd.easier: ['za łatwe', 'za latwe', 'za łatwo', 'łatwizna'],
    VoiceCmd.pain: ['boli', 'ból', 'bol', 'kontuzja'],
    VoiceCmd.remaining: ['ile zostało', 'ile jeszcze', 'czas'],
  };

  Future<bool> start(void Function(VoiceCmd, int?) handler) async {
    onCommand = handler;
    try {
      available = await _stt.initialize(
        onStatus: _onStatus,
        onError: (e) {
          error = e.errorMsg;
          listening = false;
          notifyListeners();
          _scheduleRestart(const Duration(milliseconds: 800));
        },
      );
    } catch (e) {
      error = '$e';
      available = false;
    }
    if (!available) {
      error ??= 'Rozpoznawanie mowy niedostępne na tym telefonie.';
      notifyListeners();
      return false;
    }
    active = true;
    Voice.instance.speaking.addListener(_onSpeaking);
    await _listen();
    notifyListeners();
    return true;
  }

  Future<void> stop() async {
    active = false;
    _restart?.cancel();
    Voice.instance.speaking.removeListener(_onSpeaking);
    try {
      await _stt.cancel();
    } catch (_) {}
    listening = false;
    notifyListeners();
  }

  void _onSpeaking() {
    if (!active) return;
    if (Voice.instance.speaking.value) {
      _stt.cancel();
      listening = false;
      notifyListeners();
    } else {
      _scheduleRestart(const Duration(milliseconds: 350));
    }
  }

  void _onStatus(String s) {
    if (s == 'notListening' || s == 'done') {
      listening = false;
      notifyListeners();
      _scheduleRestart(const Duration(milliseconds: 300));
    } else if (s == 'listening') {
      listening = true;
      notifyListeners();
    }
  }

  void _scheduleRestart(Duration d) {
    _restart?.cancel();
    if (!active) return;
    _restart = Timer(d, () {
      if (active && !Voice.instance.speaking.value && !_stt.isListening) _listen();
    });
  }

  Future<void> _listen() async {
    if (!active || Voice.instance.speaking.value) return;
    _handledThisUtterance = false;
    try {
      await _stt.listen(
        onResult: _onResult,
        listenOptions: SpeechListenOptions(
          localeId: 'pl_PL',
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 4),
          partialResults: true,
          cancelOnError: false,
          listenMode: ListenMode.confirmation,
        ),
      );
    } catch (e) {
      debugPrint('STT: $e');
      _scheduleRestart(const Duration(seconds: 1));
    }
  }

  void _onResult(SpeechRecognitionResult r) {
    final text = r.recognizedWords.toLowerCase();
    lastHeard = text;
    notifyListeners();
    if (_handledThisUtterance) return;
    final cmd = parse(text);
    if (cmd != null) {
      _handledThisUtterance = true;
      onCommand?.call(cmd.$1, cmd.$2);
      // krótka pauza i nowa sesja, żeby kolejne słowo było osobną komendą
      _stt.cancel();
      _scheduleRestart(const Duration(milliseconds: 600));
    }
  }

  /// Rozpoznanie komendy w tekście (testowalne bez telefonu).
  static (VoiceCmd, int?)? parse(String text) {
    final t = ' ${text.toLowerCase()} ';
    // najpierw dłuższe frazy (np. „za trudne” przed „trudne”)
    for (final cmd in [VoiceCmd.harder, VoiceCmd.easier, VoiceCmd.remaining, VoiceCmd.done, VoiceCmd.pain]) {
      if (_words[cmd]!.any((w) => t.contains(' $w') || t.contains('$w '))) return (cmd, null);
    }
    final n = RegExp(r'\b(\d{1,2})\b').firstMatch(t);
    if (n != null) return (VoiceCmd.setReps, int.parse(n.group(1)!));
    for (final cmd in [VoiceCmd.next, VoiceCmd.pause, VoiceCmd.resume, VoiceCmd.prev]) {
      if (_words[cmd]!.any((w) => RegExp('(^|\\s)${RegExp.escape(w)}(\\s|\$)').hasMatch(t))) return (cmd, null);
    }
    return null;
  }
}
