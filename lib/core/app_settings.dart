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

  Future<void> load() async {
    try {
      _p = await SharedPreferences.getInstance();
      theme = _p!.getString('theme') ?? 'dark';
      haptics = _p!.getBool('haptics') ?? true;
      anim3d = _p!.getBool('anim3d') ?? true;
      technique = _p!.getBool('technique') ?? true;
    } catch (e) {
      debugPrint('Ustawienia: $e');
    }
  }

  void set({String? theme, bool? haptics, bool? anim3d, bool? technique}) {
    if (theme != null) this.theme = theme;
    if (haptics != null) this.haptics = haptics;
    if (anim3d != null) this.anim3d = anim3d;
    if (technique != null) this.technique = technique;
    final p = _p;
    if (p != null) {
      p.setString('theme', this.theme);
      p.setBool('haptics', this.haptics);
      p.setBool('anim3d', this.anim3d);
      p.setBool('technique', this.technique);
    }
    notifyListeners();
  }
}
