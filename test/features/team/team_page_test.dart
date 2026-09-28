import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safe_family_app_nguyenthanhloi/core/theme/app_theme.dart';
import 'package:safe_family_app_nguyenthanhloi/features/team/data/member_photo_store.dart';
import 'package:safe_family_app_nguyenthanhloi/features/team/data/photo_picker.dart';
import 'package:safe_family_app_nguyenthanhloi/features/team/data/team_member.dart';
import 'package:safe_family_app_nguyenthanhloi/features/team/data/team_repository.dart';
import 'package:safe_family_app_nguyenthanhloi/features/team/presentation/team_page.dart';

import '../../helpers/fake_launcher.dart';

class FakeTeamRepository implements TeamRepository {
  FakeTeamRepository(this.members, {this.photoAssets = const {}});

  final List<TeamMember> members;
  final Set<String> photoAssets;

  @override
  Future<List<TeamMember>> loadMembers() async => members;

  @override
  Future<Set<String>> loadPhotoAssets() async => photoAssets;
}

class FakePhotoStore implements MemberPhotoStore {
  final saved = <String, String>{};

  @override
  Future<String?> photoPath(String memberId) async => saved[memberId];

  @override
  Future<String> savePhoto(String memberId, String sourcePath) async =>
      saved[memberId] = '/app/team_photos/$memberId.jpg';

  @override
  Future<void> deletePhoto(String memberId) async => saved.remove(memberId);
}

class FakePicker implements PhotoPicker {
  FakePicker(this.result);

  final String? result;

  @override
  Future<String?> pickFromGallery() async => result;
}

const _members = [
  TeamMember(
    id: 'nguyenthanhloi',
    fullName: 'Nguyễn Thành Lợi',
    email: 'loi@example.com',
  ),
  TeamMember(id: 'hongocphu', fullName: 'Hồ Ngọc Phú'),
  TeamMember(id: 'phamdinhgiabao', fullName: 'Phạm Đinh Gia Bảo'),
  TeamMember(id: 'phuongbaokhoi', fullName: 'Phương Bảo Khôi'),
];

void main() {
  late FakePhotoStore store;
  late FakeLauncher launcher;

  setUp(() {
    store = FakePhotoStore();
    launcher = FakeLauncher();
  });

  Future<void> pumpTeam(
    WidgetTester tester, {
    bool uploadEnabled = true,
    Set<String> photoAssets = const {},
    String? pickedPath = '/gallery/IMG_1.jpg',
  }) async {
    // Màn hình điện thoại nhỏ 360 × 640 dp — kiểm tra không tràn chữ.
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: TeamPage(
          repository: FakeTeamRepository(_members, photoAssets: photoAssets),
          photoStore: store,
          photoPicker: FakePicker(pickedPath),
          launcher: launcher,
          photoUploadEnabled: uploadEnabled,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> swipeNext(WidgetTester tester) async {
    await tester.drag(find.byType(PageView), const Offset(-300, 0));
    await tester.pumpAndSettle();
  }

  testWidgets('lướt đủ 4 thẻ, có chấm trang và "1/4"', (tester) async {
    await pumpTeam(tester);

    for (final (i, member) in _members.indexed) {
      expect(find.text('${i + 1}/4'), findsOneWidget);
      expect(find.text(member.fullName), findsOneWidget);
      if (i < _members.length - 1) await swipeNext(tester);
    }

    // Hết thẻ thì không lướt tiếp được.
    await swipeNext(tester);
    expect(find.text('4/4'), findsOneWidget);
  });

  testWidgets('trường trống hiện "Chưa cập nhật"', (tester) async {
    await pumpTeam(tester);

    await swipeNext(tester); // Hồ Ngọc Phú: không có gì
    expect(find.text('Chưa cập nhật'), findsWidgets);
  });

  testWidgets('MỞ: tải ảnh lên → hiện Đổi ảnh / Xóa ảnh', (tester) async {
    await pumpTeam(tester);

    await tester.tap(find.text('Tải ảnh lên').first);
    await tester.pumpAndSettle();

    expect(store.saved['nguyenthanhloi'], isNotNull);
    expect(find.text('Đổi ảnh'), findsOneWidget);
    expect(find.text('Xóa ảnh'), findsOneWidget);

    await tester.tap(find.text('Xóa ảnh'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Xóa'));
    await tester.pumpAndSettle();

    expect(store.saved, isEmpty);
    expect(find.text('Tải ảnh lên'), findsWidgets);
  });

  testWidgets('bấm Hủy khi chọn ảnh thì không lưu gì', (tester) async {
    await pumpTeam(tester, pickedPath: null);

    await tester.tap(find.text('Tải ảnh lên').first);
    await tester.pumpAndSettle();

    expect(store.saved, isEmpty);
  });

  testWidgets('KHÓA: không còn nút tải/đổi/xóa ảnh ở cả 4 thẻ', (tester) async {
    store.saved['hongocphu'] = '/app/team_photos/hongocphu.jpg';
    await pumpTeam(tester, uploadEnabled: false);

    for (var i = 0; i < _members.length; i++) {
      expect(find.text('Tải ảnh lên'), findsNothing);
      expect(find.text('Đổi ảnh'), findsNothing);
      expect(find.text('Xóa ảnh'), findsNothing);
      await swipeNext(tester);
    }
  });

  testWidgets('đã có ảnh cố định trong assets thì ẩn nút tải ảnh', (
    tester,
  ) async {
    await pumpTeam(tester, photoAssets: {'assets/team/nguyenthanhloi.jpg'});

    // Thẻ 1 (có ảnh cố định) không có nút; thẻ 2 ló ra bên cạnh vẫn có.
    expect(find.text('Tải ảnh lên'), findsOneWidget);
    await swipeNext(tester);
    expect(find.text('Tải ảnh lên'), findsWidgets);
  });

  testWidgets('bấm email thì mở app mail', (tester) async {
    await pumpTeam(tester);

    await tester.tap(find.text('loi@example.com'));
    await tester.pump();

    expect(launcher.emailed, ['loi@example.com']);
  });
}
