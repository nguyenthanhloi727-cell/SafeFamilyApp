import 'package:flutter/foundation.dart';

import '../data/profile_repository.dart';

/// State của tab Cá nhân: tên phụ huynh.
///
/// Các hàm ghi dữ liệu có thể ném lỗi lưu trữ — giao diện bắt và báo SnackBar.
class ProfileController extends ChangeNotifier {
  ProfileController(this._repository);

  static const defaultParentName = 'Phụ huynh';

  final ProfileRepository _repository;

  bool _isLoading = true;
  Object? _loadError;
  String? _parentName;
  bool _disposed = false;

  bool get isLoading => _isLoading;
  Object? get loadError => _loadError;

  /// `true` nếu phụ huynh đã tự đặt tên.
  bool get hasParentName => _parentName?.isNotEmpty ?? false;
  String get parentName => hasParentName ? _parentName! : defaultParentName;

  Future<void> load() async {
    _isLoading = true;
    _loadError = null;
    _notify();
    try {
      _parentName = await _repository.loadParentName();
    } catch (error) {
      _loadError = error;
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  Future<void> renameParent(String name) async {
    await _repository.saveParentName(name);
    _parentName = name.trim();
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
