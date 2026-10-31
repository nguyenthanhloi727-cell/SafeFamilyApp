import 'package:shared_preferences/shared_preferences.dart';

import '../network/api_client.dart';

/// Một app mới cài trên máy con cần báo cho mẹ.
class NewAppAlert {
  const NewAppAlert(this.deviceName, this.app);
  final String deviceName;
  final InstalledAppInfo app;

  String get title => 'SafeFamily';
  String get body => '$deviceName vừa cài ${app.label}, chờ bạn duyệt';
}

/// Hỏi server xem máy con nào có app mới cài (trạng thái `new`) chưa báo mẹ. Mốc "đã báo tới app số mấy" lưu
/// theo từng máy con. Giống [ChildRequestAlertChecker]: lần đầu thấy một máy vẫn báo các app đang chờ (việc còn dở
/// cần mẹ quyết định). Chỉ gọi `GET devices` và `GET devices/{id}/apps?status=new`; chỉ tên app + tên gói.
/// Chạy trong tác vụ nền 15 phút cùng các cảnh báo khác.
class NewAppAlertChecker {
  NewAppAlertChecker(this._api);
  final ApiClient _api;

  static String cursorKey(int deviceId) => 'new_app_alert_cursor_$deviceId';

  Future<List<NewAppAlert>> check() async {
    final prefs = await SharedPreferences.getInstance();
    final alerts = <NewAppAlert>[];
    for (final d in await _api.listDevices()) {
      final key = cursorKey(d.id);
      final cursor = prefs.getInt(key) ?? 0;
      final apps = await _api.getDeviceApps(d.id, status: AppStatus.isNew);
      final fresh = apps.where((a) => a.id > cursor).toList()
        ..sort((a, b) => a.id.compareTo(b.id));
      if (fresh.isEmpty) continue;
      for (final a in fresh) {
        alerts.add(NewAppAlert(d.name, a));
      }
      await prefs.setInt(key, fresh.last.id);
    }
    return alerts;
  }
}
