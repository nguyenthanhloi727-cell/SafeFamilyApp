import 'package:shared_preferences/shared_preferences.dart';

import 'profile_repository.dart';

/// Lưu trên máy bằng shared_preferences.
class LocalProfileRepository implements ProfileRepository {
  LocalProfileRepository({SharedPreferencesAsync? prefs})
    : _prefs = prefs ?? SharedPreferencesAsync();

  static const parentNameKey = 'profile.parent_name';

  final SharedPreferencesAsync _prefs;

  @override
  Future<String?> loadParentName() => _prefs.getString(parentNameKey);

  @override
  Future<void> saveParentName(String name) =>
      _prefs.setString(parentNameKey, name.trim());
}
