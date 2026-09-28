/// Một liên hệ trong danh bạ gia đình.
class FamilyContact {
  const FamilyContact({
    required this.id,
    required this.label,
    required this.phone,
    required this.order,
  });

  final String id;

  /// Tên gọi: Mẹ, Bố, Ông… hoặc tên tự gõ.
  final String label;

  /// Số đã chuẩn hoá (xem `phone_number.dart`). Chuỗi rỗng = chưa có số.
  final String phone;

  /// Thứ tự hiển thị, nhỏ đứng trước.
  final int order;

  bool get hasPhone => phone.isNotEmpty;

  FamilyContact copyWith({String? label, String? phone, int? order}) {
    return FamilyContact(
      id: id,
      label: label ?? this.label,
      phone: phone ?? this.phone,
      order: order ?? this.order,
    );
  }

  Map<String, Object> toJson() => {
    'id': id,
    'label': label,
    'phone': phone,
    'order': order,
  };

  factory FamilyContact.fromJson(Map<String, Object?> json) {
    return FamilyContact(
      id: json['id']! as String,
      label: json['label']! as String,
      phone: (json['phone'] as String?) ?? '',
      order: (json['order'] as int?) ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FamilyContact &&
      other.id == id &&
      other.label == label &&
      other.phone == phone &&
      other.order == order;

  @override
  int get hashCode => Object.hash(id, label, phone, order);
}
