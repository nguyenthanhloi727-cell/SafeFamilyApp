import 'package:flutter/foundation.dart';

import '../data/member_photo.dart';
import '../data/member_photo_store.dart';
import '../data/team_member.dart';
import '../data/team_repository.dart';

/// State của tab Nhóm: danh sách thành viên + ảnh của từng người.
class TeamController extends ChangeNotifier {
  TeamController(this._repository, this._photoStore);

  final TeamRepository _repository;
  final MemberPhotoStore _photoStore;

  bool _isLoading = true;
  Object? _loadError;
  List<TeamMember> _members = const [];
  Set<String> _photoAssets = const {};
  final _uploadedPaths = <String, String>{};
  bool _disposed = false;

  bool get isLoading => _isLoading;
  Object? get loadError => _loadError;
  List<TeamMember> get members => _members;

  Future<void> load() async {
    _isLoading = true;
    _loadError = null;
    _notify();
    try {
      _members = await _repository.loadMembers();
      _photoAssets = await _repository.loadPhotoAssets();
      _uploadedPaths.clear();
      for (final member in _members) {
        final path = await _photoStore.photoPath(member.id);
        if (path != null) _uploadedPaths[member.id] = path;
      }
    } catch (error) {
      _loadError = error;
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  MemberPhoto photoOf(TeamMember member) => resolveMemberPhoto(
    memberId: member.id,
    photoAssets: _photoAssets,
    uploadedPath: _uploadedPaths[member.id],
  );

  /// Chép ảnh [sourcePath] vào kho của app và dùng làm ảnh của [member].
  Future<void> setUploadedPhoto(TeamMember member, String sourcePath) async {
    _uploadedPaths[member.id] = await _photoStore.savePhoto(
      member.id,
      sourcePath,
    );
    _notify();
  }

  Future<void> removeUploadedPhoto(TeamMember member) async {
    await _photoStore.deletePhoto(member.id);
    _uploadedPaths.remove(member.id);
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
