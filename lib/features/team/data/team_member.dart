/// Thành viên nhóm, đọc từ `assets/team/members.json`.
///
/// Trường để trống trong JSON → `null` → giao diện hiện "Chưa cập nhật".
class TeamMember {
  const TeamMember({
    required this.id,
    required this.fullName,
    this.studentId,
    this.email,
    this.role,
    this.className,
  });

  /// Mã không dấu, cũng là tên file ảnh: `assets/team/<id>.jpg`.
  final String id;
  final String fullName;
  final String? studentId;
  final String? email;
  final String? role;
  final String? className;

  factory TeamMember.fromJson(Map<String, Object?> json) {
    String? optional(String key) {
      final value = (json[key] as String?)?.trim();
      return (value == null || value.isEmpty) ? null : value;
    }

    final id = optional('id');
    final fullName = optional('fullName');
    if (id == null || fullName == null) {
      throw FormatException('Thành viên thiếu "id" hoặc "fullName": $json');
    }
    return TeamMember(
      id: id,
      fullName: fullName,
      studentId: optional('studentId'),
      email: optional('email'),
      role: optional('role'),
      className: optional('className'),
    );
  }
}
