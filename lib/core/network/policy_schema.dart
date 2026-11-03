import '../../features/profile/data/family_contact.dart';

/// Schema gói luật của máy con (`PUT /api/devices/{id}/policy`, docs/API_DAY_DU.md, API-04).
///
/// ```json
/// {
///   "schemaVersion": 3,
///   "timeLimit": { ...cấu hình giới hạn thời gian (TimeLimitConfig.toJson)... },
///   "appLock": { "blocked": ["com.google.android.youtube"], "schedules": [] },
///   "contacts": [ { "label": "Mẹ", "phone": "0901234567", "sos": true }, { "label": "Ông", "phone": "0912345678", "sos": false } ]
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
/// phải cả danh bạ. Máy con bản cũ chỉ hiểu phiên bản 1 sẽ giữ luật cũ.
///
/// Phiên bản 3 (T10) mở `contacts` thành danh bạ của con: tối đa [maxContacts]
/// liên hệ, trong đó tối đa [maxSos] liên hệ `sos:true`; nhãn ≤ [maxLabel] ký tự
/// (khớp server `PolicyRules`). Thiếu `sos`: phiên bản < 3 là true, từ 3 là false.
/// Máy con bản cũ (chỉ hiểu ≤ 2) gặp phiên bản 3 sẽ giữ luật cũ.
abstract final class PolicySchema {
  static const version = 3;
  static const maxContacts = 20;
  static const maxSos = 3;
  static const maxLabel = 30;

  /// Khớp `MaxPolicyBytes` của server.
  static const maxBytes = 64 * 1024;

  /// Mục `contacts` của luật: liên hệ có số, tối đa [maxContacts], nhãn cắt còn [maxLabel].
  /// Chỉ [maxSos] liên hệ SOS đầu tiên giữ `sos:true`, các liên hệ SOS thừa thành `false`.
  static List<Map<String, Object>> contactsJson(
    Iterable<FamilyContact> contacts,
  ) {
    var sosLeft = maxSos;
    return [
      for (final c in contacts.where((c) => c.hasPhone).take(maxContacts))
        {
          'label': c.label.length > maxLabel
              ? c.label.substring(0, maxLabel)
              : c.label,
          'phone': c.phone,
          'sos': c.emergency && sosLeft-- > 0,
        },
    ];
  }
}
