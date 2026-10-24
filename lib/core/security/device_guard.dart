import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Thời gian cho vào màn Cài đặt sau khi phụ huynh đã xác thực.
const settingsAllowSeconds = 180;

/// Một lần đọc đồng hồ không chỉnh được của Android.
class ClockReading {
  const ClockReading({required this.elapsed, required this.bootCount});

  /// `SystemClock.elapsedRealtime()`: thời gian từ lúc máy khởi động
  /// (tính cả lúc ngủ). Đổi giờ hệ thống không ảnh hưởng.
  final Duration elapsed;

  /// Số lần máy đã khởi động; đổi nghĩa là máy vừa khởi động lại.
  /// `-1` = máy không cho đọc.
  final int bootCount;

  /// Cùng một lần khởi động với [bootCount] khác (đều đọc được).
  bool sameBootAs(int other) => bootCount != -1 && bootCount == other;
}

/// Trạng thái hai lớp chống bypass phía Android.
class DeviceGuardStatus {
  const DeviceGuardStatus({
    this.settingsGuard = false,
    this.deviceAdmin = false,
  });

  /// Dịch vụ Trợ năng "Bảo vệ cài đặt" đang chạy.
  final bool settingsGuard;

  /// Quản trị thiết bị đang bật (chống gỡ app).
  final bool deviceAdmin;

  bool get allOn => settingsGuard && deviceAdmin;
}

/// Phần chống bypass nói chuyện với Android (kênh `safefamily/guard`).
abstract interface class DeviceGuardPlatform {
  /// Đọc đồng hồ không chỉnh được; `null` nếu không đọc được.
  Future<ClockReading?> readClock();

  Future<DeviceGuardStatus> status();

  /// Bật/tắt chặn màn Cài đặt của SafeFamily (bật khi đã đặt PIN).
  Future<void> setProtection(bool enabled);

  /// Phụ huynh vừa xác thực: cho vào màn hệ thống [seconds] giây.
  Future<void> allowSettings(int seconds);

  /// `true` nếu dịch vụ vừa chặn một màn nguy hiểm và cần hỏi PIN.
  Future<bool> consumeChallenge();

  /// `true` nếu con vừa bấm "Xin thêm giờ" trên màn chặn.
  Future<bool> consumeExtraTimeRequest();

  Future<void> requestDeviceAdmin();
}

/// Bản dùng khi không có Android (test, máy tính): không làm gì.
class NoDeviceGuard implements DeviceGuardPlatform {
  const NoDeviceGuard();

  @override
  Future<ClockReading?> readClock() async => null;

  @override
  Future<DeviceGuardStatus> status() async => const DeviceGuardStatus();

  @override
  Future<void> setProtection(bool enabled) async {}

  @override
  Future<void> allowSettings(int seconds) async {}

  @override
  Future<bool> consumeChallenge() async => false;

  @override
  Future<bool> consumeExtraTimeRequest() async => false;

  @override
  Future<void> requestDeviceAdmin() async {}
}

class MethodChannelDeviceGuard implements DeviceGuardPlatform {
  const MethodChannelDeviceGuard();

  static const channel = MethodChannel('safefamily/guard');

  @override
  Future<ClockReading?> readClock() async {
    try {
      final map = await channel.invokeMapMethod<String, Object?>('clock');
      final elapsed = map?['elapsedMillis'];
      final boot = map?['bootCount'];
      if (elapsed is! num || boot is! num) return null;
      return ClockReading(
        elapsed: Duration(milliseconds: elapsed.toInt()),
        bootCount: boot.toInt(),
      );
    } on PlatformException catch (error) {
      debugPrint('Không đọc được đồng hồ máy: $error');
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<DeviceGuardStatus> status() async {
    try {
      final map = await channel.invokeMapMethod<String, bool>('status');
      return DeviceGuardStatus(
        settingsGuard: map?['guardService'] ?? false,
        deviceAdmin: map?['deviceAdmin'] ?? false,
      );
    } on PlatformException {
      return const DeviceGuardStatus();
    } on MissingPluginException {
      return const DeviceGuardStatus();
    }
  }

  @override
  Future<void> setProtection(bool enabled) => _call('setProtection', enabled);

  @override
  Future<void> allowSettings(int seconds) => _call('allowSettings', seconds);

  @override
  Future<bool> consumeChallenge() async {
    try {
      return await channel.invokeMethod<bool>('consumeChallenge') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> consumeExtraTimeRequest() async {
    try {
      return await channel.invokeMethod<bool>('consumeExtraTime') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> requestDeviceAdmin() => _call('requestDeviceAdmin');

  Future<void> _call(String method, [Object? arguments]) async {
    try {
      await channel.invokeMethod<void>(method, arguments);
    } on PlatformException catch (error) {
      debugPrint('Lỗi gọi $method: $error');
    } on MissingPluginException {
      // Không phải Android (test): bỏ qua.
    }
  }
}

/// Bật `FLAG_SECURE` (chặn chụp/ghi màn hình, ẩn ảnh trong đa nhiệm) trong lúc
/// màn PIN và màn mã khôi phục đang hiện. Đếm số màn đang cần để màn này đóng
/// không tắt cờ của màn kia.
abstract final class SecureScreen {
  static int _holders = 0;

  static Future<void> acquire() async {
    if (_holders++ == 0) await _set(true);
  }

  static Future<void> release() async {
    if (_holders > 0 && --_holders == 0) await _set(false);
  }

  static Future<void> _set(bool on) async {
    try {
      await MethodChannelDeviceGuard.channel.invokeMethod<void>(
        'setSecure',
        on,
      );
    } on PlatformException {
      // Không bật được thì thôi, không làm hỏng màn nhập PIN.
    } on MissingPluginException {
      // Không phải Android (test): bỏ qua.
    }
  }
}
