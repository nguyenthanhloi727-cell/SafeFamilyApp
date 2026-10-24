import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// App mới cài đang chờ phụ huynh duyệt.
class PendingApp {
  const PendingApp({required this.packageName, required this.label});

  final String packageName;
  final String label;
}

/// Duyệt app mới cài (kênh `safefamily/new_apps`). Việc phát hiện và chặn
/// chạy ở native; Dart chỉ hiện danh sách và ghi quyết định "cho phép".
abstract interface class NewAppPlatform {
  Future<bool> isEnabled();
  Future<void> setEnabled(bool enabled);

  /// Quét lại rồi trả danh sách app đang chờ duyệt.
  Future<List<PendingApp>> pending();

  Future<void> approve(String packageName);

  /// `true` nếu phụ huynh vừa bấm thông báo / nút "Nhờ bố mẹ duyệt".
  Future<bool> consumeReviewRequest();

  Future<bool> notificationsAllowed();
  Future<void> requestNotifications();
}

class MethodChannelNewApp implements NewAppPlatform {
  const MethodChannelNewApp();

  static const _channel = MethodChannel('safefamily/new_apps');

  @override
  Future<bool> isEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('enabled') ?? true;
    } on PlatformException {
      return true;
    } on MissingPluginException {
      return true;
    }
  }

  @override
  Future<void> setEnabled(bool enabled) =>
      _channel.invokeMethod<void>('setEnabled', enabled);

  @override
  Future<List<PendingApp>> pending() async {
    try {
      final raw = await _channel.invokeListMethod<Map<Object?, Object?>>(
        'pending',
      );
      return [
        for (final item in raw ?? const <Map<Object?, Object?>>[])
          PendingApp(
            packageName: item['package'] as String,
            label: (item['label'] as String?) ?? item['package'] as String,
          ),
      ];
    } on PlatformException catch (error) {
      debugPrint('Duyệt app mới: không đọc được danh sách ($error)');
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  @override
  Future<void> approve(String packageName) =>
      _channel.invokeMethod<void>('approve', packageName);

  @override
  Future<bool> consumeReviewRequest() async {
    try {
      return await _channel.invokeMethod<bool>('consumeReview') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> notificationsAllowed() async {
    try {
      return await _channel.invokeMethod<bool>('notificationsAllowed') ?? true;
    } on PlatformException {
      return true;
    } on MissingPluginException {
      return true;
    }
  }

  @override
  Future<void> requestNotifications() async {
    try {
      await _channel.invokeMethod<void>('requestNotifications');
    } on PlatformException {
      // Không xin được thì thôi: app vẫn bị chặn, chỉ thiếu thông báo.
    } on MissingPluginException {
      // Không phải Android (test): bỏ qua.
    }
  }
}
