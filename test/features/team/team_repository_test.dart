import 'package:flutter_test/flutter_test.dart';

import 'package:safe_family_app_nguyenthanhloi/features/team/data/team_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('assets/team/members.json', () {
    test('đủ 4 người đúng thứ tự, id không dấu', () async {
      final members = await AssetTeamRepository().loadMembers();

      expect(members.map((m) => m.fullName), [
        'Nguyễn Thành Lợi',
        'Hồ Ngọc Phú',
        'Phạm Đinh Gia Bảo',
        'Phương Bảo Khôi',
      ]);
      expect(members.map((m) => m.id), [
        'nguyenthanhloi',
        'hongocphu',
        'phamdinhgiabao',
        'phuongbaokhoi',
      ]);
    });
  });

  group('parseTeamMembers', () {
    test('đọc đủ các trường', () {
      final members = parseTeamMembers('''
        [{"id": "a", "fullName": "Nguyễn Văn A", "studentId": "2200001",
          "email": "a@st.edu.vn", "role": "Nhóm trưởng", "className": "22DTH1"}]
      ''');

      final a = members.single;
      expect(a.id, 'a');
      expect(a.fullName, 'Nguyễn Văn A');
      expect(a.studentId, '2200001');
      expect(a.email, 'a@st.edu.vn');
      expect(a.role, 'Nhóm trưởng');
      expect(a.className, '22DTH1');
    });

    test('trường rỗng, chỉ có khoảng trắng hoặc thiếu → null', () {
      final a = parseTeamMembers(
        '[{"id": "a", "fullName": "A", "studentId": "", "email": "   "}]',
      ).single;

      expect(a.studentId, isNull);
      expect(a.email, isNull);
      expect(a.role, isNull);
      expect(a.className, isNull);
    });

    test('thiếu id hoặc họ tên thì báo lỗi rõ ràng', () {
      expect(
        () => parseTeamMembers('[{"id": "", "fullName": "A"}]'),
        throwsFormatException,
      );
      expect(() => parseTeamMembers('[{"id": "a"}]'), throwsFormatException);
    });
  });
}
