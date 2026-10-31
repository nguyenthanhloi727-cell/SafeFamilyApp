import 'package:shared_preferences/shared_preferences.dart';

import '../network/api_client.dart';

/// Một yêu cầu mới của con cần báo cho mẹ.
class ChildRequestAlert {
  const ChildRequestAlert(this.deviceName, this.request);
  final String deviceName;
  final ChildRequestInfo request;

  String get title => 'SafeFamily';
  String get body => switch (request.kind) {
    RequestKind.extraTime =>
      request.minutes == null
          ? '$deviceName xin thêm giờ'
          : '$deviceName xin thêm ${request.minutes} phút',
    RequestKind.studyDone => '$deviceName báo đã học xong, chờ bạn duyệt',
    _ => '$deviceName có yêu cầu mới',
  };
}

/// Hỏi server xem máy con nào có yêu cầu ĐANG CHỜ mới kể từ lần trước (xin thêm giờ, "đã học xong").
///
/// Mốc "đã báo tới yêu cầu số mấy" lưu theo từng máy con. Khác cảnh báo hàng rào: lần đầu thấy một máy
/// con vẫn báo các yêu cầu đang chờ (việc còn dở cần mẹ quyết định), chỉ không báo lại yêu cầu đã duyệt.
/// Chỉ gọi `GET devices` và `GET devices/{id}/requests?status=pending`; chỉ loại yêu cầu và số phút,
/// không có nội dung nào khác. Chạy trong tác vụ nền 15 phút cùng cảnh báo vào/ra vùng.
class ChildRequestAlertChecker {
  ChildRequestAlertChecker(this._api);
  final ApiClient _api;

  static String cursorKey(int deviceId) => 'request_alert_cursor_$deviceId';

  Future<List<ChildRequestAlert>> check() async {
    final prefs = await SharedPreferences.getInstance();
    final alerts = <ChildRequestAlert>[];
    for (final d in await _api.listDevices()) {
      final key = cursorKey(d.id);
      final cursor = prefs.getInt(key) ?? 0;
      final pending = await _api.getRequests(d.id, status: 'pending');
      final fresh = pending.where((r) => r.id > cursor).toList()
        ..sort((a, b) => a.id.compareTo(b.id));
      if (fresh.isEmpty) continue;
      for (final r in fresh) {
        alerts.add(ChildRequestAlert(d.name, r));
      }
      await prefs.setInt(key, fresh.last.id);
    }
    return alerts;
  }
}
