import 'package:shared_preferences/shared_preferences.dart';

import '../network/api_client.dart';

/// Một cảnh báo vào/ra vùng cần báo cho mẹ.
class GeofenceAlert {
  const GeofenceAlert(this.deviceName, this.event);
  final String deviceName;
  final GeofenceEventInfo event;

  String get title => 'SafeFamily';
  String get body =>
      '$deviceName ${event.isExit ? 'đã rời' : 'đã đến'} ${event.name}';
}

/// Hỏi server xem máy con nào có sự kiện hàng rào mới kể từ lần trước.
///
/// Mốc "đã thấy tới sự kiện số mấy" lưu trong SharedPreferences theo từng máy con.
/// Lần đầu thấy một máy con chỉ ghi mốc, không báo lại cả lịch sử cũ.
/// Dùng chung cho tác vụ nền (app mẹ đóng) và có thể gọi khi app đang mở.
class GeofenceAlertChecker {
  GeofenceAlertChecker(this._api);
  final ApiClient _api;

  static String cursorKey(int deviceId) => 'geofence_alert_cursor_$deviceId';

  Future<List<GeofenceAlert>> check() async {
    final prefs = await SharedPreferences.getInstance();
    final alerts = <GeofenceAlert>[];
    for (final d in await _api.listDevices()) {
      final key = cursorKey(d.id);
      final cursor = prefs.getInt(key);
      final events = await _api.getGeofenceEvents(d.id, afterId: cursor ?? 0);
      if (events.isEmpty) continue;
      final latest = events.map((e) => e.id).reduce((a, b) => a > b ? a : b);
      if (cursor != null) {
        for (final e in events) {
          if (e.id > cursor) alerts.add(GeofenceAlert(d.name, e));
        }
      }
      await prefs.setInt(key, latest);
    }
    return alerts;
  }
}
