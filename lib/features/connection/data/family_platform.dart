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

  /// Con xin thêm giờ (`extra_time`, kèm số phút) hoặc báo học xong (`study_done`).
  Future<void> queueRequest(String kind, {int minutes = 0});

  /// Trạng thái theo loại yêu cầu: `pending` / `approved` / `denied`. Loại chưa gửi thì không có khóa.
  Future<Map<String, String>> requestStatuses();

  /// Lần đồng bộ thành công gần nhất với máy mẹ; null nếu chưa lần nào.
  Future<DateTime?> lastSyncAt();
  Future<LocationPermissionStatus> locationStatus();
  Future<void> requestLocation();
  Future<bool> requestBackgroundLocation();
}

/// Kết quả mở khóa khu phụ huynh gửi sang Kotlin để ghi vào nhật ký hoạt động cho mẹ (T8).
/// Chỉ có loại sự kiện; máy chưa ghép đôi (kể cả máy mẹ) thì Kotlin bỏ qua.
enum ParentAuthActivity {
  unlocked('parent_unlocked'),
  failed('parent_auth_failed');

  const ParentAuthActivity(this.kind);
  final String kind;
}

/// Báo Kotlin ghi một sự kiện mở khóa phụ huynh. Không có kênh (test, nền tảng khác): không làm gì.
Future<void> reportParentAuthActivity(ParentAuthActivity activity) async {
  try {
    await const MethodChannel(
      'safefamily/family',
    ).invokeMethod<void>('logActivity', {'kind': activity.kind});
  } on MissingPluginException {
    return;
  } on PlatformException {
    return;
  }
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
  Future<void> queueRequest(String kind, {int minutes = 0}) =>
      _call<void>('queueRequest', {'kind': kind, 'minutes': minutes});

  @override
  Future<Map<String, String>> requestStatuses() async {
    final m = await _call<Map<Object?, Object?>>('requestStatuses');
    return {
      for (final e in (m ?? const {}).entries) '${e.key}': '${e.value}',
    };
  }

  @override
  Future<DateTime?> lastSyncAt() async {
    final ms = await _call<int>('lastSyncMs') ?? 0;
    return ms > 0 ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
  }

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
