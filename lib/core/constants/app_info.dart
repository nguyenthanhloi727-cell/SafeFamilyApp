/// Thông tin app theo thành viên nhóm.
///
/// [ownerName] do `tool/rename.dart` cập nhật — không sửa tay.
abstract final class AppInfo {
  static const appName = 'SafeFamily';
  static const ownerName = 'Nguyễn Thành Lợi';

  /// Tên hiển thị, trùng với nhãn app trên điện thoại.
  static const displayName = '$appName - $ownerName';
}
