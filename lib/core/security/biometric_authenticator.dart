import 'dart:convert';
import 'dart:math';

import 'package:biometric_storage/biometric_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import 'secure_store.dart';
import 'unlock_log.dart';

/// Khả năng sinh trắc học của máy.
class BiometricCapability {
  const BiometricCapability({
    this.fingerprintHardware = false,
    this.faceHardware = false,
    this.irisHardware = false,
    this.enrolled = false,
  });

  static const none = BiometricCapability();

  /// Máy có cảm biến vân tay.
  final bool fingerprintHardware;

  /// Máy có nhận diện khuôn mặt LOẠI APP DÙNG ĐƯỢC (Android khai báo
  /// FEATURE_FACE). Mở khóa khuôn mặt "tiện lợi" chỉ dùng cho màn hình khóa
  /// thì không tính.
  final bool faceHardware;
  final bool irisHardware;

  /// Đã đăng ký sinh trắc loại MẠNH (biometric_storage chỉ nhận loại này)
  /// → app gọi được.
  final bool enrolled;

  bool get hasHardware => fingerprintHardware || faceHardware || irisHardware;

  /// Có thể dùng sinh trắc để mở khóa trong app ngay bây giờ.
  bool get canAuthenticate => enrolled;

  /// "Vân tay", "Vân tay, Khuôn mặt"… hoặc chuỗi rỗng.
  String get supportedLabel => [
    if (fingerprintHardware) 'Vân tay',
    if (faceHardware) 'Khuôn mặt',
    if (irisHardware) 'Mống mắt',
  ].join(', ');

  /// Phương thức ghi vào nhật ký khi mở khóa bằng sinh trắc thành công.
  /// Android không cho biết người dùng vừa dùng vân tay hay khuôn mặt.
  UnlockMethod get logMethod {
    if (fingerprintHardware && !faceHardware) return UnlockMethod.fingerprint;
    if (faceHardware && !fingerprintHardware) return UnlockMethod.face;
    return UnlockMethod.biometric;
  }
}

enum BiometricResult {
  success,

  /// Người dùng bấm "Dùng mã PIN" / đóng hộp thoại.
  canceled,

  /// Sai quá nhiều lần, Android tạm khóa sinh trắc.
  lockedOut,

  /// Máy không có / chưa đăng ký sinh trắc, hoặc tạm thời không dùng được.
  notAvailable,

  /// Chìa khóa phụ huynh không còn dùng được (máy đổi/xóa vân tay, hoặc chưa
  /// bật theo cách mới) → phải tắt sinh trắc và bật lại.
  invalidated,
  failed,
}

/// Xác thực sinh trắc cho [ParentGuard]; tách interface để test giả lập được.
abstract interface class BiometricAuthenticator {
  Future<BiometricCapability> capability();

  /// Bật: tạo chìa khóa phụ huynh mới (hiện hộp thoại sinh trắc).
  Future<BiometricResult> enroll(String reason);

  /// Mở khóa: đọc chìa khóa phụ huynh (hiện hộp thoại sinh trắc).
  Future<BiometricResult> authenticate(String reason);

  /// Tắt: xóa chìa khóa phụ huynh.
  Future<void> disable();
}

/// Kho biometric_storage chứa chìa khóa phụ huynh; tách ra để test giả lập.
abstract interface class BiometricVault {
  Future<CanAuthenticateResponse> canAuthenticate();

  /// `null` khi kho trống — kể cả khi gói tự xóa kho vì khóa Keystore mất
  /// hiệu lực (máy đổi/xóa vân tay).
  Future<String?> read(String reason);
  Future<void> write(String value, String reason);
  Future<void> delete();
}

class BiometricStorageVault implements BiometricVault {
  static const _name = 'parent_key';

  Future<BiometricStorageFile>? _file;

  Future<BiometricStorageFile> _open() async {
    // Mặc định: bắt buộc xác thực MỖI LẦN, chỉ sinh trắc mạnh
    // (Android: BIOMETRIC_STRONG, không nhận mật khẩu màn hình).
    _file ??= BiometricStorage().getStorage(
      _name,
      options: StorageFileInitOptions(androidBiometricOnly: true),
    );
    try {
      return await _file!;
    } catch (_) {
      _file = null;
      rethrow;
    }
  }

  static PromptInfo _prompt(String reason, {required String negative}) =>
      PromptInfo(
        androidPromptInfo: AndroidPromptInfo(
          title: 'Xác thực phụ huynh',
          subtitle: reason,
          negativeButton: negative,
          confirmationRequired: false,
        ),
        iosPromptInfo: IosPromptInfo(saveTitle: reason, accessTitle: reason),
      );

  @override
  Future<CanAuthenticateResponse> canAuthenticate() =>
      BiometricStorage().canAuthenticate();

  @override
  Future<String?> read(String reason) async => (await _open()).read(
    promptInfo: _prompt(reason, negative: 'Dùng mã PIN'),
  );

  @override
  Future<void> write(String value, String reason) async => (await _open())
      .write(value, promptInfo: _prompt(reason, negative: 'Hủy'));

  @override
  Future<void> delete() async => (await _open()).delete();
}

/// Mở khóa bằng "chìa khóa phụ huynh": 32 byte ngẫu nhiên nằm trong kho
/// biometric_storage (chỉ đọc được sau khi quét sinh trắc); SecureStore chỉ
/// giữ bản băm SHA-256 để so.
class BiometricStorageAuthenticator implements BiometricAuthenticator {
  BiometricStorageAuthenticator({
    required this._store,
    BiometricVault? vault,
    Random? random,
  }) : _vault = vault ?? BiometricStorageVault(),
       _random = random ?? Random.secure();

  static const keyHashKey = 'guard.biometric_key_hash';

  static const _hardwareChannel = MethodChannel(
    'safefamily/biometric_hardware',
  );

  final SecureStore _store;
  final BiometricVault _vault;
  final Random _random;

  @override
  Future<BiometricCapability> capability() async {
    var hardware = const <String, bool>{};
    try {
      hardware =
          await _hardwareChannel.invokeMapMethod<String, bool>('features') ??
          const {};
    } catch (_) {
      // Kênh không có (chạy ngoài Android) → coi như không có phần cứng.
    }
    return BiometricCapability(
      fingerprintHardware: hardware['fingerprint'] ?? false,
      faceHardware: hardware['face'] ?? false,
      irisHardware: hardware['iris'] ?? false,
      enrolled: await _canAuthenticate(),
    );
  }

  @override
  Future<BiometricResult> enroll(String reason) async {
    final key = base64Url.encode(
      List<int>.generate(32, (_) => _random.nextInt(256)),
    );
    await disable();
    try {
      await _vault.write(key, reason);
    } on AuthException catch (e) {
      return _authError(e);
    } catch (_) {
      return BiometricResult.failed;
    }
    await _store.write(keyHashKey, _hash(key));
    return BiometricResult.success;
  }

  @override
  Future<BiometricResult> authenticate(String reason) async {
    final expected = await _store.read(keyHashKey);
    if (expected == null) return BiometricResult.invalidated;
    try {
      final key = await _vault.read(reason);
      if (key == null) {
        await disable();
        return BiometricResult.invalidated;
      }
      return _hash(key) == expected
          ? BiometricResult.success
          : BiometricResult.failed;
    } on AuthException catch (e) {
      return _authError(e);
    } catch (_) {
      return BiometricResult.failed;
    }
  }

  @override
  Future<void> disable() async {
    await _store.delete(keyHashKey);
    try {
      await _vault.delete();
    } catch (_) {
      // Kho chưa từng tạo / đã bị gói xóa → không còn gì để xóa.
    }
  }

  Future<bool> _canAuthenticate() async {
    try {
      return await _vault.canAuthenticate() == CanAuthenticateResponse.success;
    } catch (_) {
      return false;
    }
  }

  /// Android: gói chỉ phân biệt hủy/hết giờ; mọi lỗi khác của BiometricPrompt
  /// (kể cả khóa tạm khi sai 5 lần — mã 7) đều thành `unknown`.
  Future<BiometricResult> _authError(AuthException e) async {
    switch (e.code) {
      case AuthExceptionCode.userCanceled ||
          AuthExceptionCode.canceled ||
          AuthExceptionCode.timeout:
        return BiometricResult.canceled;
      default:
        // Lỗi của chính gói (chưa gắn / Activity không hiện được hộp thoại).
        if (e.message.toLowerCase().contains('activity')) {
          return BiometricResult.failed;
        }
        // Máy vẫn báo dùng được sinh trắc mà hộp thoại báo lỗi → khóa tạm.
        return await _canAuthenticate()
            ? BiometricResult.lockedOut
            : BiometricResult.notAvailable;
    }
  }

  static String _hash(String key) =>
      sha256.convert(utf8.encode(key)).toString();
}
