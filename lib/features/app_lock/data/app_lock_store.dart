import 'package:shared_preferences/shared_preferences.dart';

import '../domain/temp_unlock.dart';

/// Lưu trên máy: app đang mở tạm + đã ghi nhật ký "bị vô hiệu hóa" chưa.
class AppLockStore {
  AppLockStore({SharedPreferencesAsync? prefs})
    : _prefs = prefs ?? SharedPreferencesAsync();

  static const unlocksKey = 'app_lock.temp_unlocks';
  static const disabledLoggedKey = 'app_lock.disabled_logged';

  final SharedPreferencesAsync _prefs;

  Future<TempUnlocks> loadUnlocks() async =>
      TempUnlocks.fromJson(await _prefs.getString(unlocksKey));

  Future<void> saveUnlocks(TempUnlocks unlocks) => unlocks.isEmpty
      ? _prefs.remove(unlocksKey)
      : _prefs.setString(unlocksKey, unlocks.toJson());

  Future<bool> disabledLogged() async =>
      await _prefs.getBool(disabledLoggedKey) ?? false;

  Future<void> setDisabledLogged(bool value) =>
      _prefs.setBool(disabledLoggedKey, value);
}
