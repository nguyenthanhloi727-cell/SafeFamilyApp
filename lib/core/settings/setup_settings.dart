import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cờ `setup_done`: wizard cấp quyền lần đầu đã đi hết (hoặc bỏ qua) chưa.
/// Gỡ cài lại app thì cờ mất, wizard hiện lại.
class SetupSettings extends ChangeNotifier {
  SetupSettings({SharedPreferencesAsync? prefs})
    : _prefs = prefs ?? SharedPreferencesAsync();

  static const storageKey = 'setup_done';

  final SharedPreferencesAsync _prefs;
  bool _loaded = false;
  bool _done = false;

  bool get isLoaded => _loaded;
  bool get isDone => _done;

  Future<void> load() async {
    try {
      _done = await _prefs.getBool(storageKey) ?? false;
    } catch (_) {
      // Không đọc được thì coi như chưa xong: hiện wizard còn hơn bỏ sót quyền.
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> markDone() async {
    if (_done) return;
    _done = true;
    notifyListeners();
    try {
      await _prefs.setBool(storageKey, true);
    } catch (_) {
      // Lưu hỏng: lần mở sau wizard hiện lại, không mất quyền nào.
    }
  }
}

/// Đưa [SetupSettings] xuống cây widget.
class SetupSettingsScope extends InheritedNotifier<SetupSettings> {
  const SetupSettingsScope({
    super.key,
    required SetupSettings settings,
    required super.child,
  }) : super(notifier: settings);

  static SetupSettings? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<SetupSettingsScope>()
      ?.notifier;
}
