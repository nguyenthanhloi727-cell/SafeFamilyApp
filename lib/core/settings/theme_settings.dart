import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Chế độ sáng/tối đang chọn, lưu trên máy. Mặc định: sáng.
class ThemeSettings extends ChangeNotifier {
  ThemeSettings({SharedPreferencesAsync? prefs})
    : _prefs = prefs ?? SharedPreferencesAsync();

  static const storageKey = 'settings.theme_mode';

  final SharedPreferencesAsync _prefs;
  ThemeMode _mode = ThemeMode.light;

  ThemeMode get mode => _mode;

  Future<void> load() async {
    try {
      final saved = await _prefs.getString(storageKey);
      _mode = ThemeMode.values.firstWhere(
        (m) => m.name == saved,
        orElse: () => ThemeMode.light,
      );
      notifyListeners();
    } catch (_) {
      // Không đọc được thì giữ mặc định.
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    await _prefs.setString(storageKey, mode.name);
  }
}

/// Đưa [ThemeSettings] xuống cây widget (đặt ở trên MaterialApp).
class ThemeSettingsScope extends InheritedNotifier<ThemeSettings> {
  const ThemeSettingsScope({
    super.key,
    required ThemeSettings settings,
    required super.child,
  }) : super(notifier: settings);

  static ThemeSettings? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ThemeSettingsScope>()
      ?.notifier;
}
