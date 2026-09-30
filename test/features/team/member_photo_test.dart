import 'package:flutter_test/flutter_test.dart';

import 'package:safe_family_app/features/team/data/member_photo.dart';

void main() {
  group('resolveMemberPhoto — thứ tự ưu tiên', () {
    test('1. có ảnh trong assets → dùng assets, bỏ qua ảnh tải lên', () {
      final photo = resolveMemberPhoto(
        memberId: 'hongocphu',
        photoAssets: {'assets/team/hongocphu.jpg'},
        uploadedPath: '/data/team_photos/hongocphu_1.jpg',
      );

      expect(photo, isA<AssetMemberPhoto>());
      expect(
        (photo as AssetMemberPhoto).assetPath,
        'assets/team/hongocphu.jpg',
      );
    });

    test('2. không có assets, có ảnh tải lên → dùng ảnh tải lên', () {
      final photo = resolveMemberPhoto(
        memberId: 'hongocphu',
        photoAssets: {'assets/team/nguoikhac.jpg'},
        uploadedPath: '/data/team_photos/hongocphu_1.jpg',
      );

      expect(photo, isA<UploadedMemberPhoto>());
      expect(
        (photo as UploadedMemberPhoto).filePath,
        '/data/team_photos/hongocphu_1.jpg',
      );
    });

    test('3. không có gì → chữ cái đầu', () {
      final photo = resolveMemberPhoto(
        memberId: 'hongocphu',
        photoAssets: const {},
      );

      expect(photo, isA<InitialsMemberPhoto>());
    });
  });
}
