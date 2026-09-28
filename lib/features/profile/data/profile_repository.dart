import 'family_contact.dart';

/// Nơi lưu hồ sơ phụ huynh và danh bạ gia đình.
///
/// Giao diện chỉ phụ thuộc interface này. Muốn lưu lên server thì viết
/// thêm một bản cài đặt khác, không phải sửa giao diện.
abstract interface class ProfileRepository {
  /// Tên phụ huynh; `null` nếu chưa đặt.
  Future<String?> loadParentName();

  Future<void> saveParentName(String name);

  /// Danh bạ theo [FamilyContact.order]. Lần đầu tạo sẵn "Mẹ", "Bố" chưa có số.
  Future<List<FamilyContact>> loadContacts();

  /// Thêm vào cuối danh sách, trả về liên hệ vừa tạo.
  Future<FamilyContact> addContact({required String label, String phone = ''});

  Future<void> updateContact(FamilyContact contact);

  Future<void> deleteContact(String id);
}
