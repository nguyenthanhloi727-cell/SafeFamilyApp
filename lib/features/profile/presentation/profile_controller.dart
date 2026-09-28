import 'package:flutter/foundation.dart';

import '../data/family_contact.dart';
import '../data/profile_repository.dart';

/// State của tab Cá nhân: tên phụ huynh + danh bạ gia đình.
///
/// Các hàm ghi dữ liệu có thể ném lỗi lưu trữ — giao diện bắt và báo SnackBar.
class ProfileController extends ChangeNotifier {
  ProfileController(this._repository);

  static const defaultParentName = 'Phụ huynh';

  final ProfileRepository _repository;

  bool _isLoading = true;
  Object? _loadError;
  String? _parentName;
  List<FamilyContact> _contacts = const [];
  bool _disposed = false;

  bool get isLoading => _isLoading;
  Object? get loadError => _loadError;
  List<FamilyContact> get contacts => _contacts;

  /// `true` nếu phụ huynh đã tự đặt tên.
  bool get hasParentName => _parentName?.isNotEmpty ?? false;
  String get parentName => hasParentName ? _parentName! : defaultParentName;

  Future<void> load() async {
    _isLoading = true;
    _loadError = null;
    _notify();
    try {
      _parentName = await _repository.loadParentName();
      _contacts = await _repository.loadContacts();
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

  Future<void> addContact({
    required String label,
    required String phone,
  }) async {
    await _repository.addContact(label: label, phone: phone);
    await _reloadContacts();
  }

  Future<void> updateContact(FamilyContact contact) async {
    await _repository.updateContact(contact);
    await _reloadContacts();
  }

  Future<void> deleteContact(String id) async {
    await _repository.deleteContact(id);
    await _reloadContacts();
  }

  Future<void> _reloadContacts() async {
    _contacts = await _repository.loadContacts();
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
