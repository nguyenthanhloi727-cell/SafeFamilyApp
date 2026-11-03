import 'package:shared_preferences/shared_preferences.dart';

/// Mốc "mẹ đã xem nhật ký hoạt động tới dòng số mấy", lưu theo từng máy con. Dùng để hiện số dòng mới ở Trang chủ.
/// Không có SharedPreferences (test dựng khung) thì coi như chưa xem gì, không ném lỗi.
class ActivitySeen {
  const ActivitySeen._();

  static String key(int deviceId) => 'activity_seen_$deviceId';

  static Future<int> get(int deviceId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(key(deviceId)) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Chỉ tiến lên, không lùi.
  static Future<void> set(int deviceId, int lastId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (lastId > (prefs.getInt(key(deviceId)) ?? 0)) {
        await prefs.setInt(key(deviceId), lastId);
      }
    } catch (_) {
      // Không lưu được thì lần sau hiện lại số mới, không sao.
    }
  }
}
