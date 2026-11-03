import '../../features/profile/data/family_contact.dart';

/// Schema gói luật của máy con (`PUT /api/devices/{id}/policy`, docs/API_DAY_DU.md, API-04).
///
/// ```json
/// {
///   "schemaVersion": 2,
///   "timeLimit": { ...cấu hình giới hạn thời gian (TimeLimitConfig.toJson)... },
///   "appLock": { "blocked": ["com.google.android.youtube"], "schedules": [] },
///   "contacts": [ { "label": "Mẹ", "phone": "0901234567", "sos": true } ]
/// }
/// ```
///
/// Server lưu nguyên khối, chỉ kiểm tra JSON hợp lệ và kích thước. Máy con
/// (Kotlin `FamilySync.pullPolicy`) mới là nơi hiểu nội dung. Máy mẹ không giữ
/// luật riêng: `PolicySync` sửa từng phần trên luật của máy con. Thêm trường mới
/// thì thêm ở cuối, không đổi nghĩa trường cũ; đổi nghĩa thì tăng [version]
/// (máy con gặp phiên bản lớn hơn mình hiểu sẽ bỏ qua và giữ luật cũ).
///
/// Phiên bản 2 (API-13) thêm `contacts`: CHỈ các số khẩn cấp (SOS) mẹ chọn, không
/// phải cả danh bạ. Tối đa [maxContacts] số; nhãn ≤ [maxLabel] ký tự (khớp server
/// `PolicyRules`). Máy con bản cũ chỉ hiểu phiên bản 1 sẽ giữ luật cũ.
abstract final class PolicySchema {
  static const version = 2;
  static const maxContacts = 3;
  static const maxLabel = 30;

  /// Khớp `MaxPolicyBytes` của server.
  static const maxBytes = 64 * 1024;

  /// Mục `contacts` của luật: chỉ số SOS có số, tối đa [maxContacts], nhãn cắt còn [maxLabel].
  static List<Map<String, Object>> sosJson(
    Iterable<FamilyContact> contacts,
  ) => [
    for (final c
        in contacts.where((c) => c.emergency && c.hasPhone).take(maxContacts))
      {
        'label': c.label.length > maxLabel
            ? c.label.substring(0, maxLabel)
            : c.label,
        'phone': c.phone,
        'sos': true,
      },
  ];
}
