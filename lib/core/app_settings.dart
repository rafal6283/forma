import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ustawienia urządzenia (wspólne dla wszystkich osób): motyw, wibracje, animacje.
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final instance = AppSettings._();

  SharedPreferences? _p;

  /// 'system' / 'light' / 'dark'
  String theme = 'dark';
  bool haptics = true;

  /// Postać 3D w podglądzie i odtwarzaczu (miniatury zawsze 2D).
  bool anim3d = true;

  /// Podświetlanie pracujących mięśni i strzałki ruchu na animacji.
  bool technique = true;

  /// Tempo powtórzeń w seriach (3 s w dół, 1 s pauzy, 1 s w górę) z sygnałami i liczeniem.
  bool tempo = false;

  Future<void> load() async {
    try {
      _p = await SharedPreferences.getInstance();
      theme = _p!.getString('theme') ?? 'dark';
      haptics = _p!.getBool('haptics') ?? true;
      anim3d = _p!.getBool('anim3d') ?? true;
      technique = _p!.getBool('technique') ?? true;
      tempo = _p!.getBool('tempo') ?? false;
    } catch (e) {
      debugPrint('Ustawienia: $e');
    }
  }

  void set({String? theme, bool? haptics, bool? anim3d, bool? technique, bool? tempo}) {
    if (theme != null) this.theme = theme;
    if (haptics != null) this.haptics = haptics;
    if (anim3d != null) this.anim3d = anim3d;
    if (technique != null) this.technique = technique;
    if (tempo != null) this.tempo = tempo;
    final p = _p;
    if (p != null) {
      p.setString('theme', this.theme);
      p.setBool('haptics', this.haptics);
      p.setBool('anim3d', this.anim3d);
      p.setBool('technique', this.technique);
      p.setBool('tempo', this.tempo);
    }
    notifyListeners();
  }
}
