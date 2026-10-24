/// Một liên hệ trong danh bạ gia đình.
class FamilyContact {
  const FamilyContact({
    required this.id,
    required this.label,
    required this.phone,
    required this.order,
    this.emergency = false,
  });

  final String id;

  /// Tên gọi: Mẹ, Bố, Ông… hoặc tên tự gõ.
  final String label;

  /// Số đã chuẩn hoá (xem `phone_number.dart`). Chuỗi rỗng = chưa có số.
  final String phone;

  /// Thứ tự hiển thị, nhỏ đứng trước.
  final int order;

  /// Liên hệ khẩn cấp: nút SOS trên màn chặn gọi số này (tối đa một người).
  final bool emergency;

  bool get hasPhone => phone.isNotEmpty;

  FamilyContact copyWith({
    String? label,
    String? phone,
    int? order,
    bool? emergency,
  }) {
    return FamilyContact(
      id: id,
      label: label ?? this.label,
      phone: phone ?? this.phone,
      order: order ?? this.order,
      emergency: emergency ?? this.emergency,
    );
  }

  Map<String, Object> toJson() => {
    'id': id,
    'label': label,
    'phone': phone,
    'order': order,
    'emergency': emergency,
  };

  factory FamilyContact.fromJson(Map<String, Object?> json) {
    return FamilyContact(
      id: json['id']! as String,
      label: json['label']! as String,
      phone: (json['phone'] as String?) ?? '',
      order: (json['order'] as int?) ?? 0,
      emergency: (json['emergency'] as bool?) ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FamilyContact &&
      other.id == id &&
      other.label == label &&
      other.phone == phone &&
      other.order == order &&
      other.emergency == emergency;

  @override
  int get hashCode => Object.hash(id, label, phone, order, emergency);
}
