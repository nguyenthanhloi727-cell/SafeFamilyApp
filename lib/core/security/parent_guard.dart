import 'package:flutter/widgets.dart';

import 'biometric_authenticator.dart';
import 'lockout_policy.dart';
import 'pin_hasher.dart';
import 'secure_store.dart';
import 'unlock_log.dart';

/// Kết quả kiểm tra một lần nhập PIN.
sealed class PinCheckResult {
  const PinCheckResult();
}

final class PinAccepted extends PinCheckResult {
  const PinAccepted();
}

final class PinRejected extends PinCheckResult {
  const PinRejected(this.attemptsLeft);

  /// Số lần còn được sai trước khi bị khóa.
  final int attemptsLeft;
}

final class PinLocked extends PinCheckResult {
  const PinLocked(this.until);
  final DateTime until;
}

/// Một lượt hỏi PIN: giao diện gọi [check] cho mỗi lần nhập.
class PinPromptSession {
  const PinPromptSession({
    required this.action,
    required this.check,
    required this.lockedUntil,
    this.notice,
  });

  /// Thao tác đang cần mở khóa, ví dụ "Sửa danh bạ".
  final String action;

  /// Lý do phải nhập PIN (ví dụ sinh trắc bị khóa tạm thời).
  final String? notice;

  final Future<PinCheckResult> Function(String pin) check;

  /// Đang bị khóa tới lúc nào (`null` = không khóa).
  final DateTime? Function() lockedUntil;
}

/// Giao diện hiện bàn phím PIN; trả về `true` khi PIN đúng, `false` khi hủy.
typedef PinPrompt = Future<bool> Function(PinPromptSession session);

/// Thời gian chờ khu vực phụ huynh được chọn.
const parentAreaTimeoutChoices = [1, 5, 15];
const defaultParentAreaTimeoutMinutes = 5;

/// Dịch vụ khóa phụ huynh dùng chung (lib/core/security).
///
/// - [require]: luôn hỏi xác thực — ưu tiên sinh trắc (nếu máy hỗ trợ và đã
///   bật), không được thì nhập PIN.
/// - [requireParentArea]: vào khu vực phụ huynh; không hỏi lại nếu vừa xác
///   thực và app chưa vào nền quá thời gian chờ (ngoài chế độ trẻ em).
/// - [requireInChildMode]: chỉ hỏi khi đang ở chế độ trẻ em.
class ParentGuard extends ChangeNotifier {
  ParentGuard({
    required SecureStore store,
    required this._biometrics,
    this._hasher = const PinHasher(),
    DateTime Function()? clock,
  }) : _store = store,
       _clock = clock ?? DateTime.now,
       log = UnlockLog(store);

  static const pinKey = 'guard.pin';
  static const failuresKey = 'guard.failures';
  static const lockedUntilKey = 'guard.locked_until';
  static const biometricKey = 'guard.biometric';
  static const timeoutKey = 'guard.timeout_minutes';
  static const childModeKey = 'guard.child_mode';

  final SecureStore _store;
  final BiometricAuthenticator _biometrics;
  final PinHasher _hasher;
  final DateTime Function() _clock;
  final UnlockLog log;

  bool _loaded = false;
  String? _pinHash;
  int _failures = 0;
  DateTime? _lockedUntil;
  bool _biometricEnabled = false;
  int _timeoutMinutes = defaultParentAreaTimeoutMinutes;
  bool _childMode = false;
  BiometricCapability _capability = BiometricCapability.none;

  DateTime? _sessionStartedAt;
  DateTime? _backgroundedAt;
  AppLifecycleListener? _lifecycle;
  bool _disposed = false;

  bool get isLoaded => _loaded;

  /// Đã đặt PIN phụ huynh (xong màn thiết lập lần đầu).
  bool get isConfigured => _pinHash != null;
  bool get childMode => _childMode;
  bool get biometricEnabled => _biometricEnabled;
  int get timeoutMinutes => _timeoutMinutes;
  BiometricCapability get capability => _capability;

  /// Sinh trắc sẽ được dùng khi hỏi xác thực.
  bool get usesBiometric => _biometricEnabled && _capability.canAuthenticate;

  /// Còn bị khóa nhập PIN tới lúc nào (`null` = không khóa).
  DateTime? get lockedUntil {
    final until = _lockedUntil;
    return until != null && until.isAfter(_clock()) ? until : null;
  }

  /// Phụ huynh đã xác thực và phiên chưa hết hạn.
  bool get hasParentSession => _sessionStartedAt != null;

  Future<void> load() async {
    _pinHash = await _store.read(pinKey);
    _failures = int.tryParse(await _store.read(failuresKey) ?? '') ?? 0;
    final until = int.tryParse(await _store.read(lockedUntilKey) ?? '');
    _lockedUntil = until == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(until);
    _biometricEnabled = await _store.read(biometricKey) == 'true';
    final timeout = int.tryParse(await _store.read(timeoutKey) ?? '');
    _timeoutMinutes = parentAreaTimeoutChoices.contains(timeout)
        ? timeout!
        : defaultParentAreaTimeoutMinutes;
    _childMode = await _store.read(childModeKey) == 'true';
    await refreshCapability();
    _loaded = true;
    _notify();
  }

  Future<void> refreshCapability() async {
    _capability = await _biometrics.capability();
    _notify();
  }

  // ---------------------------------------------------------------- PIN

  /// Đặt PIN lần đầu (màn thiết lập). Phụ huynh vừa đặt PIN → mở phiên.
  Future<void> setupPin(String pin) async {
    assert(pinChoiceProblem(pin) == null);
    _pinHash = await _hasher.hash(pin);
    await _store.write(pinKey, _pinHash!);
    await _resetFailures();
    _sessionStartedAt = _clock();
    _notify();
  }

  /// Đổi PIN. Gọi [require] trước khi cho đổi.
  Future<void> changePin(String newPin) => setupPin(newPin);

  /// Kiểm tra một lần nhập PIN, đếm sai và khóa theo [lockDurationAfter].
  Future<PinCheckResult> checkPin(String pin, {required String action}) async {
    final locked = lockedUntil;
    if (locked != null) return PinLocked(locked);

    final stored = _pinHash;
    final ok = stored != null && await _hasher.verify(pin, stored);
    if (ok) {
      await _resetFailures();
      await _record(action, UnlockMethod.pin, UnlockResult.success);
      return const PinAccepted();
    }

    _failures++;
    await _store.write(failuresKey, '$_failures');
    await _record(action, UnlockMethod.pin, UnlockResult.failure);
    final lock = lockDurationAfter(_failures);
    if (lock != null) {
      _lockedUntil = _clock().add(lock);
      await _store.write(
        lockedUntilKey,
        '${_lockedUntil!.millisecondsSinceEpoch}',
      );
      _notify();
      return PinLocked(_lockedUntil!);
    }
    return PinRejected(pinAttemptsBeforeLock - _failures);
  }

  Future<void> _resetFailures() async {
    _failures = 0;
    _lockedUntil = null;
    await _store.delete(failuresKey);
    await _store.delete(lockedUntilKey);
  }

  // ------------------------------------------------------ Xác thực chung

  /// Luôn hỏi xác thực. Trả về `true` nếu phụ huynh xác thực thành công.
  Future<bool> require(String action, {required PinPrompt promptPin}) async {
    if (!isConfigured) return true;

    String? notice;
    if (usesBiometric && lockedUntil == null) {
      final result = await _biometrics.authenticate(
        'Xác thực phụ huynh để: $action',
      );
      switch (result) {
        case BiometricResult.success:
          await _resetFailures();
          await _record(action, _capability.logMethod, UnlockResult.success);
          _startSession();
          return true;
        case BiometricResult.canceled:
          await _record(action, _capability.logMethod, UnlockResult.canceled);
        case BiometricResult.lockedOut:
          await _record(action, _capability.logMethod, UnlockResult.failure);
          notice =
              'Vân tay/khuôn mặt tạm bị khóa do sai nhiều lần. '
              'Hãy nhập mã PIN.';
        case BiometricResult.notAvailable:
          notice =
              'Không dùng được vân tay/khuôn mặt lúc này. '
              'Hãy nhập mã PIN.';
          await refreshCapability();
        case BiometricResult.failed:
          await _record(action, _capability.logMethod, UnlockResult.failure);
          notice = 'Xác thực sinh trắc không thành công. Hãy nhập mã PIN.';
      }
    }

    var attempted = false;
    final ok = await promptPin(
      PinPromptSession(
        action: action,
        notice: notice,
        lockedUntil: () => lockedUntil,
        check: (pin) {
          attempted = true;
          return checkPin(pin, action: action);
        },
      ),
    );
    if (ok) {
      _startSession();
    } else if (!attempted) {
      await _record(action, UnlockMethod.pin, UnlockResult.canceled);
    }
    return ok;
  }

  /// Vào khu vực phụ huynh (cài đặt, quản lý, nhật ký…).
  Future<bool> requireParentArea(
    String action, {
    required PinPrompt promptPin,
  }) async {
    if (!_childMode && hasParentSession) return true;
    return require(action, promptPin: promptPin);
  }

  /// Thao tác chỉ cần khóa khi đang ở chế độ trẻ em.
  Future<bool> requireInChildMode(
    String action, {
    required PinPrompt promptPin,
  }) async {
    if (!_childMode) return true;
    return require(action, promptPin: promptPin);
  }

  // ------------------------------------------------------ Chế độ trẻ em

  /// Bật: không cần xác thực. Thoát: bắt buộc xác thực.
  Future<bool> setChildMode(bool on, {required PinPrompt promptPin}) async {
    if (on == _childMode) return true;
    if (!on && !await require('Thoát chế độ trẻ em', promptPin: promptPin)) {
      return false;
    }
    _childMode = on;
    if (on) _sessionStartedAt = null; // con cầm máy → khép khu vực phụ huynh
    await _store.write(childModeKey, '$on');
    _notify();
    return true;
  }

  // -------------------------------------------------- Cài đặt bảo mật

  /// Bật/tắt sinh trắc. Luôn xác thực trước; bật thì phải quét thành công.
  Future<bool> setBiometricEnabled(
    bool enabled, {
    required PinPrompt promptPin,
  }) async {
    if (enabled == _biometricEnabled) return true;
    final action = enabled ? 'Bật mở khóa sinh trắc' : 'Tắt mở khóa sinh trắc';
    if (!await require(action, promptPin: promptPin)) return false;
    if (enabled && !await confirmBiometric(action)) return false;
    await _saveBiometricEnabled(enabled);
    return true;
  }

  /// Quét thử sinh trắc (khi bật lần đầu).
  Future<bool> confirmBiometric(String action) async {
    await refreshCapability();
    if (!_capability.canAuthenticate) return false;
    final result = await _biometrics.authenticate(
      'Quét để bật mở khóa bằng vân tay/khuôn mặt',
    );
    final ok = result == BiometricResult.success;
    await _record(
      action,
      _capability.logMethod,
      ok
          ? UnlockResult.success
          : result == BiometricResult.canceled
          ? UnlockResult.canceled
          : UnlockResult.failure,
    );
    return ok;
  }

  /// Dùng ở màn thiết lập lần đầu (phụ huynh vừa đặt PIN, đã quét thử).
  Future<void> enableBiometricAfterSetup() => _saveBiometricEnabled(true);

  Future<void> _saveBiometricEnabled(bool enabled) async {
    _biometricEnabled = enabled;
    await _store.write(biometricKey, '$enabled');
    _notify();
  }

  Future<bool> setTimeoutMinutes(
    int minutes, {
    required PinPrompt promptPin,
  }) async {
    assert(parentAreaTimeoutChoices.contains(minutes));
    if (minutes == _timeoutMinutes) return true;
    if (!await require('Đổi thời gian chờ', promptPin: promptPin)) {
      return false;
    }
    _timeoutMinutes = minutes;
    await _store.write(timeoutKey, '$minutes');
    _notify();
    return true;
  }

  /// Xóa nhật ký — phải xác thực.
  Future<bool> clearLog({required PinPrompt promptPin}) async {
    if (!await require('Xóa nhật ký mở khóa', promptPin: promptPin)) {
      return false;
    }
    await log.clear();
    _notify();
    return true;
  }

  /// Ghi cảnh báo của hệ thống vào nhật ký (khóa ứng dụng bị vô hiệu hóa…).
  Future<void> recordWarning(String action) =>
      _record(action, UnlockMethod.system, UnlockResult.warning);

  // ------------------------------------------- Phiên & app vào nền

  void _startSession() {
    _sessionStartedAt = _clock();
    _notify();
  }

  /// Nghe app vào nền / trở lại (gọi 1 lần khi app chạy).
  void attachLifecycle() {
    _lifecycle ??= AppLifecycleListener(
      onPause: () => markBackgrounded(_clock()),
      onResume: () => markForegrounded(_clock()),
    );
  }

  void markBackgrounded(DateTime at) => _backgroundedAt ??= at;

  /// Trở lại sau quá [timeoutMinutes] → phải xác thực lại khu vực phụ huynh.
  void markForegrounded(DateTime at) {
    final since = _backgroundedAt;
    _backgroundedAt = null;
    if (since == null || _sessionStartedAt == null) return;
    if (at.difference(since) > Duration(minutes: _timeoutMinutes)) {
      _sessionStartedAt = null;
      _notify();
    }
  }

  Future<void> _record(
    String action,
    UnlockMethod method,
    UnlockResult result,
  ) async {
    await log.add(
      UnlockLogEntry(
        time: _clock(),
        action: action,
        method: method,
        result: result,
      ),
    );
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _lifecycle?.dispose();
    super.dispose();
  }
}

/// Đưa [ParentGuard] xuống cây widget.
class ParentGuardScope extends InheritedNotifier<ParentGuard> {
  const ParentGuardScope({
    super.key,
    required ParentGuard guard,
    required super.child,
  }) : super(notifier: guard);

  /// `null` khi không có (ví dụ test một màn riêng lẻ) → không khóa gì.
  static ParentGuard? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ParentGuardScope>()?.notifier;

  /// Như [maybeOf] nhưng không đăng ký rebuild (dùng trong hàm xử lý bấm nút).
  static ParentGuard? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ParentGuardScope>()?.notifier;
}
