import 'package:shared_preferences/shared_preferences.dart';

import '../network/api_client.dart';
import '../network/child_status_text.dart';

/// Một cảnh báo tamper / mất kết nối cần báo cho mẹ.
class TamperAlert {
  const TamperAlert(this.deviceName, this.alert);
  final String deviceName;
  final AlertInfo alert;

  String get title => 'SafeFamily';
  String get body => '$deviceName: ${alertLabel(alert)}';
}

/// Hỏi server xem máy con nào có cảnh báo mới (đổi giờ, gỡ app, tắt Trợ năng / Quản trị thiết bị, thiếu quyền,
/// mất kết nối) kể từ lần trước. Mốc "đã xét tới cảnh báo số mấy" lưu theo từng máy con.
///
/// Cảnh báo mẹ đã đánh dấu đã đọc thì không báo lại, nhưng mốc vẫn đi qua nó. Lần đầu thấy một máy chỉ báo cảnh báo
/// CHƯA ĐỌC, tối đa [maxPerDevice] cái mới nhất mỗi lần (tránh ngập thông báo). Chỉ gọi `GET devices` và
/// `GET devices/{id}/alerts?afterId=`; dữ liệu chỉ có loại sự kiện, mã/số ngắn và thời điểm. Chạy trong tác vụ nền
/// 15 phút cùng các cảnh báo khác.
class TamperAlertChecker {
  TamperAlertChecker(this._api);
  final ApiClient _api;

  static const maxPerDevice = 5;

  static String cursorKey(int deviceId) => 'tamper_alert_cursor_$deviceId';

  Future<List<TamperAlert>> check() async {
    final prefs = await SharedPreferences.getInstance();
    final alerts = <TamperAlert>[];
    for (final d in await _api.listDevices()) {
      final key = cursorKey(d.id);
      final cursor = prefs.getInt(key) ?? 0;
      final rows = await _api.getAlerts(d.id, afterId: cursor);
      if (rows.isEmpty) continue;
      rows.sort((a, b) => a.id.compareTo(b.id));
      final fresh = [
        for (final a in rows)
          if (a.id > cursor && a.isUnread) a,
      ];
      final shown = fresh.length > maxPerDevice
          ? fresh.sublist(fresh.length - maxPerDevice)
          : fresh;
      for (final a in shown) {
        alerts.add(TamperAlert(d.name, a));
      }
      await prefs.setInt(key, rows.last.id);
    }
    return alerts;
  }
}
