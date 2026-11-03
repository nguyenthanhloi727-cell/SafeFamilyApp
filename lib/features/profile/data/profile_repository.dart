/// Nơi lưu hồ sơ phụ huynh. Danh bạ của con không nằm ở đây: nó là một phần luật của
/// máy con trên server (xem `PolicySync.loadContacts` / `setContacts`).
///
/// Giao diện chỉ phụ thuộc interface này. Muốn lưu lên server thì viết
/// thêm một bản cài đặt khác, không phải sửa giao diện.
abstract interface class ProfileRepository {
  /// Tên phụ huynh; `null` nếu chưa đặt.
  Future<String?> loadParentName();

  Future<void> saveParentName(String name);
}
