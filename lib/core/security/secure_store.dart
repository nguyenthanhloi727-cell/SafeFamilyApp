import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Kho khóa–giá trị cho dữ liệu bảo mật (PIN đã băm, trạng thái khóa, nhật ký…).
///
/// Bản thật: flutter_secure_storage (mã hóa bằng Android Keystore).
/// Test: bản trong bộ nhớ (test/helpers).
abstract interface class SecureStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterSecureStore implements SecureStore {
  const FlutterSecureStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
