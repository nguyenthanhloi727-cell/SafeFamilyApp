/// Thành viên nhóm (mục 6 của thầy). `null` = chưa có → giao diện để khung trống.
class TeamMember {
  const TeamMember({
    required this.fullName,
    this.studentId,
    this.email,
    this.role,
    this.className,
  });

  final String fullName;
  final String? studentId;
  final String? email;
  final String? role;
  final String? className;
}

const teamMembers = [
  TeamMember(fullName: 'Nguyễn Thành Lợi'),
  TeamMember(fullName: 'Hồ Ngọc Phú'),
  TeamMember(fullName: 'Phạm Đinh Gia Bảo'),
  TeamMember(fullName: 'Phương Bảo Khôi'),
];
