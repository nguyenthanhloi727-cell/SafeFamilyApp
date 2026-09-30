/// Thông tin chung của app.
abstract final class AppInfo {
  /// Tên hiển thị, trùng với nhãn app trên điện thoại.
  static const appName = 'SafeFamily';

  /// Trùng `applicationId` trong android/app/build.gradle.kts
  /// (dùng để mở trang Cài đặt của chính app).
  static const applicationId = 'com.safefamily.nguyenthanhloi';

  static const displayName = appName;
}
