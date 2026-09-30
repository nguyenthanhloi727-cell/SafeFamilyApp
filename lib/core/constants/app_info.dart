/// Thông tin app theo thành viên nhóm.
///
/// [ownerName] và [applicationId] do `tool/rename.dart` cập nhật — không sửa tay.
abstract final class AppInfo {
  static const appName = 'SafeFamily';
  static const ownerName = 'Nguyễn Thành Lợi';

  /// Trùng `applicationId` trong android/app/build.gradle.kts
  /// (dùng để mở trang Cài đặt của chính app).
  static const applicationId = 'com.safefamily.nguyenthanhloi';

  /// Tên hiển thị, trùng với nhãn app trên điện thoại (không kèm tên thành viên).
  static const displayName = appName;
}
