import 'team_repository.dart';

/// Ảnh sẽ hiển thị trên thẻ thành viên.
sealed class MemberPhoto {
  const MemberPhoto();
}

/// Ảnh cố định đóng gói trong app (`assets/team/<id>.jpg`).
class AssetMemberPhoto extends MemberPhoto {
  const AssetMemberPhoto(this.assetPath);
  final String assetPath;
}

/// Ảnh người dùng đã tải lên, nằm trong thư mục riêng của app.
class UploadedMemberPhoto extends MemberPhoto {
  const UploadedMemberPhoto(this.filePath);
  final String filePath;
}

/// Chưa có ảnh: hiện chữ cái đầu.
class InitialsMemberPhoto extends MemberPhoto {
  const InitialsMemberPhoto();
}

/// Thứ tự ưu tiên: ảnh trong assets → ảnh đã tải lên → chữ cái đầu.
MemberPhoto resolveMemberPhoto({
  required String memberId,
  required Set<String> photoAssets,
  String? uploadedPath,
}) {
  final assetPath = AssetTeamRepository.photoAssetPath(memberId);
  if (photoAssets.contains(assetPath)) return AssetMemberPhoto(assetPath);
  if (uploadedPath != null) return UploadedMemberPhoto(uploadedPath);
  return const InitialsMemberPhoto();
}
