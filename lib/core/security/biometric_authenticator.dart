import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';

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

  /// Đã đăng ký ít nhất một sinh trắc (loại yếu hoặc mạnh) → app gọi được.
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
  failed,
}

/// Bọc local_auth để test giả lập được.
abstract interface class BiometricAuthenticator {
  Future<BiometricCapability> capability();
  Future<BiometricResult> authenticate(String reason);
}

class LocalAuthBiometricAuthenticator implements BiometricAuthenticator {
  LocalAuthBiometricAuthenticator({LocalAuthentication? auth})
    : _auth = auth ?? LocalAuthentication();

  static const _hardwareChannel = MethodChannel(
    'safefamily/biometric_hardware',
  );

  final LocalAuthentication _auth;

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
    var enrolled = false;
    try {
      enrolled = (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {}
    return BiometricCapability(
      fingerprintHardware: hardware['fingerprint'] ?? false,
      faceHardware: hardware['face'] ?? false,
      irisHardware: hardware['iris'] ?? false,
      enrolled: enrolled,
    );
  }

  @override
  Future<BiometricResult> authenticate(String reason) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        authMessages: const [
          AndroidAuthMessages(
            signInTitle: 'Xác thực phụ huynh',
            signInHint: 'Chạm cảm biến vân tay hoặc nhìn vào máy',
            cancelButton: 'Dùng mã PIN',
          ),
        ],
      );
      return ok ? BiometricResult.success : BiometricResult.failed;
    } on LocalAuthException catch (e) {
      return switch (e.code) {
        LocalAuthExceptionCode.userCanceled ||
        LocalAuthExceptionCode.systemCanceled ||
        LocalAuthExceptionCode.userRequestedFallback ||
        LocalAuthExceptionCode.timeout => BiometricResult.canceled,
        LocalAuthExceptionCode.temporaryLockout ||
        LocalAuthExceptionCode.biometricLockout => BiometricResult.lockedOut,
        LocalAuthExceptionCode.noBiometricHardware ||
        LocalAuthExceptionCode.noBiometricsEnrolled ||
        LocalAuthExceptionCode.noCredentialsSet ||
        LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable ||
        LocalAuthExceptionCode.uiUnavailable => BiometricResult.notAvailable,
        _ => BiometricResult.failed,
      };
    } catch (_) {
      return BiometricResult.failed;
    }
  }
}
