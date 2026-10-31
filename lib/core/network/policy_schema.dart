import 'dart:convert';

/// Schema gói luật gửi lên `PUT /api/devices/{id}/policy` (docs/API_DAY_DU.md, API-04).
///
/// ```json
/// {
///   "schemaVersion": 1,
///   "timeLimit": { ...cấu hình giới hạn thời gian (TimeLimitConfig.toJson)... },
///   "appLock": { "blocked": ["com.google.android.youtube"], "schedules": [] }
/// }
/// ```
///
/// Server lưu nguyên khối, chỉ kiểm tra JSON hợp lệ và kích thước. Máy con
/// (Kotlin `FamilySync.pullPolicy`) mới là nơi hiểu nội dung. Thêm trường mới
/// thì thêm ở cuối, không đổi nghĩa trường cũ; đổi nghĩa thì tăng [version]
/// (máy con gặp phiên bản lớn hơn mình hiểu sẽ bỏ qua và giữ luật cũ).
abstract final class PolicySchema {
  static const version = 1;

  /// Khớp `MaxPolicyBytes` của server.
  static const maxBytes = 64 * 1024;

  /// [blocked] là các app mẹ đang khóa (kể cả đang mở tạm: mở tạm trên máy mẹ
  /// không có nghĩa là mở cho máy con).
  ///
  /// `appLock.schedules` để trống: lịch chặn theo giờ (giờ ngủ, giờ học) nằm
  /// trong `timeLimit`; `BlockSchedules` chỉ hiển thị lại chúng.
  /// TODO(verify): lịch chặn riêng từng app chưa có trong app, thêm khi có.
  static String build({
    required Map<String, dynamic> timeLimit,
    required Iterable<String> blocked,
  }) {
    final packages = blocked.toSet().toList()..sort();
    return jsonEncode({
      'schemaVersion': version,
      'timeLimit': timeLimit,
      'appLock': {'blocked': packages, 'schedules': const <Object>[]},
    });
  }

  /// Hai chuỗi JSON cùng nội dung (bỏ qua khác biệt khoảng trắng/thứ tự khóa).
  static bool sameContent(String a, String b) {
    try {
      return _canonical(jsonDecode(a)) == _canonical(jsonDecode(b));
    } on FormatException {
      return false;
    }
  }

  static String _canonical(Object? v) => jsonEncode(_sorted(v));

  static Object? _sorted(Object? v) => switch (v) {
    Map() => {
      for (final k in (v.keys.toList()..sort())) k as String: _sorted(v[k]),
    },
    List() => [for (final e in v) _sorted(e)],
    _ => v,
  };
}
