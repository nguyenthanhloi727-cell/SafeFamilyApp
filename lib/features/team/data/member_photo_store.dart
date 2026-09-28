import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lưu ảnh thành viên do người dùng tải lên.
abstract interface class MemberPhotoStore {
  /// Đường dẫn ảnh đã lưu của [memberId], hoặc `null` nếu chưa có.
  Future<String?> photoPath(String memberId);

  /// Chép [sourcePath] vào kho của app (thay ảnh cũ nếu có), trả về đường dẫn mới.
  Future<String> savePhoto(String memberId, String sourcePath);

  Future<void> deletePhoto(String memberId);
}

/// Chép ảnh vào `<thư mục riêng của app>/team_photos/`, lưu TÊN FILE bằng
/// shared_preferences. Ảnh gốc trong thư viện bị xóa thì ảnh trong app vẫn còn.
class LocalMemberPhotoStore implements MemberPhotoStore {
  LocalMemberPhotoStore({
    SharedPreferencesAsync? prefs,
    Future<Directory> Function()? baseDirectory,
  }) : _prefs = prefs ?? SharedPreferencesAsync(),
       _baseDirectory = baseDirectory ?? getApplicationDocumentsDirectory;

  static const keyPrefix = 'team.photo.';

  final SharedPreferencesAsync _prefs;
  final Future<Directory> Function() _baseDirectory;

  Future<Directory> _photosDir() async {
    final base = await _baseDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}team_photos');
    return dir.create(recursive: true);
  }

  Future<String> _pathOf(String fileName) async =>
      '${(await _photosDir()).path}${Platform.pathSeparator}$fileName';

  @override
  Future<String?> photoPath(String memberId) async {
    final fileName = await _prefs.getString('$keyPrefix$memberId');
    if (fileName == null) return null;
    final path = await _pathOf(fileName);
    if (await File(path).exists()) return path;
    // File đã mất (ví dụ người dùng xóa dữ liệu app) → quên luôn.
    await _prefs.remove('$keyPrefix$memberId');
    return null;
  }

  @override
  Future<String> savePhoto(String memberId, String sourcePath) async {
    final oldFileName = await _prefs.getString('$keyPrefix$memberId');
    // Tên mới mỗi lần để Flutter không hiện lại ảnh cũ đã cache.
    final fileName = '${memberId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final path = await _pathOf(fileName);
    await File(sourcePath).copy(path);
    await _prefs.setString('$keyPrefix$memberId', fileName);
    if (oldFileName != null && oldFileName != fileName) {
      await _deleteFile(oldFileName);
    }
    return path;
  }

  @override
  Future<void> deletePhoto(String memberId) async {
    final fileName = await _prefs.getString('$keyPrefix$memberId');
    await _prefs.remove('$keyPrefix$memberId');
    if (fileName != null) await _deleteFile(fileName);
  }

  Future<void> _deleteFile(String fileName) async {
    final file = File(await _pathOf(fileName));
    if (await file.exists()) await file.delete();
  }
}
