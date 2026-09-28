import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/foundation.dart';

import '../constants/app_info.dart';

/// Mở các trang Cài đặt của Android. Trả về `false` nếu không mở được.
abstract interface class SystemSettings {
  /// Trang thông tin của chính app (cấp lại quyền micro…).
  Future<bool> openAppSettings();

  /// Cài đặt nhập bằng giọng nói (tải thêm gói ngôn ngữ nhận giọng nói).
  Future<bool> openVoiceInputSettings();
}

class AndroidSystemSettings implements SystemSettings {
  const AndroidSystemSettings();

  @override
  Future<bool> openAppSettings() => _launch(
    const AndroidIntent(
      action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
      data: 'package:${AppInfo.applicationId}',
    ),
  );

  @override
  Future<bool> openVoiceInputSettings() async =>
      await _launch(
        const AndroidIntent(action: 'android.settings.VOICE_INPUT_SETTINGS'),
      ) ||
      // Máy không có trang riêng → mở trang Ngôn ngữ & nhập liệu.
      await _launch(
        const AndroidIntent(action: 'android.settings.INPUT_METHOD_SETTINGS'),
      );

  Future<bool> _launch(AndroidIntent intent) async {
    try {
      await intent.launch();
      return true;
    } catch (error) {
      debugPrint('Không mở được ${intent.action}: $error');
      return false;
    }
  }
}
