import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/foundation.dart';

import '../constants/app_info.dart';

/// Mở các trang Cài đặt của Android. Trả về `false` nếu không mở được.
abstract interface class SystemSettings {
  /// Trang thông tin của chính app (menu ⋮ "Cho phép cài đặt bị hạn chế"…).
  Future<bool> openAppSettings();
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
