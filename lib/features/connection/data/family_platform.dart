import 'package:flutter/services.dart';

/// Trạng thái quyền vị trí trên máy con.
class LocationPermissionStatus {
  const LocationPermissionStatus({
    this.foreground = false,
    this.background = false,
  });

  final bool foreground;

  /// "Luôn cho phép" (cần để hàng rào địa lý và vị trí chạy khi app đóng).
  final bool background;
}

/// Nói chuyện với phần Kotlin lo việc đồng bộ của máy con (kênh `safefamily/family`):
/// Dart chỉ giao địa chỉ API + token thiết bị; Kotlin tự hỏi lệnh/luật, gửi vị trí
/// và đăng ký hàng rào để vẫn chạy khi Flutter không chạy.
abstract interface class FamilyPlatform {
  Future<void> configure(String baseUrl, String token);
  Future<void> clear();
  Future<bool> syncNow();
  Future<LocationPermissionStatus> locationStatus();
  Future<void> requestLocation();
  Future<bool> requestBackgroundLocation();
}

class MethodChannelFamily implements FamilyPlatform {
  const MethodChannelFamily();

  static const _channel = MethodChannel('safefamily/family');

  // Máy không có kênh (test, nền tảng khác): coi như không làm gì, không crash.
  Future<T?> _call<T>(String method, [Object? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<void> configure(String baseUrl, String token) =>
      _call<void>('configure', {'baseUrl': baseUrl, 'token': token});

  @override
  Future<void> clear() => _call<void>('clear');

  @override
  Future<bool> syncNow() async => await _call<bool>('syncNow') ?? false;

  @override
  Future<LocationPermissionStatus> locationStatus() async {
    final m = await _call<Map<Object?, Object?>>('locationStatus');
    return LocationPermissionStatus(
      foreground: m?['foreground'] == true,
      background: m?['background'] == true,
    );
  }

  @override
  Future<void> requestLocation() => _call<void>('requestLocation');

  @override
  Future<bool> requestBackgroundLocation() async =>
      await _call<bool>('requestBackgroundLocation') ?? false;
}
