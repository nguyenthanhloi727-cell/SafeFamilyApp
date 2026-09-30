import 'package:biometric_storage/biometric_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safe_family_app/core/security/biometric_authenticator.dart';

import '../../helpers/security_fakes.dart';

/// Kho biometric_storage giả: [nextError] = lỗi của lần quét kế tiếp.
class FakeVault implements BiometricVault {
  String? content;
  Object? nextError;
  CanAuthenticateResponse can = CanAuthenticateResponse.success;
  int reads = 0;
  int writes = 0;

  void _throwIfError() {
    final e = nextError;
    nextError = null;
    if (e != null) throw e;
  }

  @override
  Future<CanAuthenticateResponse> canAuthenticate() async => can;

  @override
  Future<String?> read(String reason) async {
    reads++;
    _throwIfError();
    return content;
  }

  @override
  Future<void> write(String value, String reason) async {
    writes++;
    _throwIfError();
    content = value;
  }

  @override
  Future<void> delete() async => content = null;
}

void main() {
  late InMemorySecureStore store;
  late FakeVault vault;
  late BiometricStorageAuthenticator auth;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    store = InMemorySecureStore();
    vault = FakeVault();
    auth = BiometricStorageAuthenticator(store: store, vault: vault);
  });

  const hashKey = BiometricStorageAuthenticator.keyHashKey;

  test('bật → ghi chìa khóa vào kho, chỉ lưu bản băm', () async {
    expect(await auth.enroll('bật'), BiometricResult.success);
    expect(vault.writes, 1);
    expect(vault.content, isNotNull);
    expect(store.data[hashKey], hasLength(64)); // SHA-256 hex
    expect(store.data.values, isNot(contains(vault.content)));
  });

  test('mỗi lần bật tạo chìa khóa mới', () async {
    await auth.enroll('bật');
    final first = vault.content;
    await auth.enroll('bật lại');
    expect(vault.content, isNot(first));
  });

  test('bật → mở khóa đúng', () async {
    await auth.enroll('bật');
    expect(await auth.authenticate('mở'), BiometricResult.success);
    expect(vault.reads, 1);
  });

  test('chìa khóa trong kho sai → failed', () async {
    await auth.enroll('bật');
    vault.content = 'chìa khóa khác';
    expect(await auth.authenticate('mở'), BiometricResult.failed);
  });

  test('đọc lỗi bất thường → failed', () async {
    await auth.enroll('bật');
    vault.nextError = StateError('hỏng');
    expect(await auth.authenticate('mở'), BiometricResult.failed);
  });

  test('bấm "Dùng mã PIN" → canceled', () async {
    await auth.enroll('bật');
    vault.nextError = AuthException(AuthExceptionCode.userCanceled, 'hủy');
    expect(await auth.authenticate('mở'), BiometricResult.canceled);
  });

  test('hủy lúc bật → không lưu bản băm', () async {
    vault.nextError = AuthException(AuthExceptionCode.userCanceled, 'hủy');
    expect(await auth.enroll('bật'), BiometricResult.canceled);
    expect(store.data, isNot(contains(hashKey)));
  });

  test('sai 5 lần (Android mã 7 → unknown), máy vẫn có sinh trắc → lockedOut',
      () async {
    await auth.enroll('bật');
    vault.nextError = AuthException(
      AuthExceptionCode.unknown,
      'Bạn đã thử quá nhiều lần. Hãy dùng phương thức khoá màn hình.',
    );
    expect(await auth.authenticate('mở'), BiometricResult.lockedOut);
  });

  test('lỗi unknown và máy hết dùng được sinh trắc → notAvailable', () async {
    await auth.enroll('bật');
    vault
      ..nextError = AuthException(AuthExceptionCode.unknown, 'lỗi')
      ..can = CanAuthenticateResponse.errorHwUnavailable;
    expect(await auth.authenticate('mở'), BiometricResult.notAvailable);
  });

  test('Activity chưa sẵn sàng hiện hộp thoại → failed', () async {
    await auth.enroll('bật');
    vault.nextError = AuthException(
      AuthExceptionCode.unknown,
      'Plugin not attached to any activity.',
    );
    expect(await auth.authenticate('mở'), BiometricResult.failed);
  });

  test('máy đổi vân tay (gói tự xóa kho → đọc ra null) → invalidated, xóa băm',
      () async {
    await auth.enroll('bật');
    vault.content = null;
    expect(await auth.authenticate('mở'), BiometricResult.invalidated);
    expect(store.data, isNot(contains(hashKey)));
  });

  test('chưa bật theo cách mới (không có bản băm) → invalidated, không quét',
      () async {
    expect(await auth.authenticate('mở'), BiometricResult.invalidated);
    expect(vault.reads, 0);
  });

  test('tắt → xóa kho và bản băm', () async {
    await auth.enroll('bật');
    await auth.disable();
    expect(vault.content, isNull);
    expect(store.data, isNot(contains(hashKey)));
  });

  test('capability: canAuthenticate() quyết định enrolled', () async {
    expect((await auth.capability()).enrolled, isTrue);
    vault.can = CanAuthenticateResponse.errorNoBiometricEnrolled;
    expect((await auth.capability()).enrolled, isFalse);
  });
}
