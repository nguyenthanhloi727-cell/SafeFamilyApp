import 'package:android_intent_plus/android_intent.dart';
import 'package:app_blocker/app_blocker.dart' as blocker;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter/services.dart';

import '../../../core/constants/app_info.dart';
import '../../../core/services/system_settings.dart';
import '../app_lock_config.dart';

/// App đã cài trên máy (để chọn chặn).
class InstalledApp {
  const InstalledApp({
    required this.packageName,
    required this.name,
    this.icon,
    this.isSystemApp = false,
  });

  final String packageName;
  final String name;

  /// Icon dạng PNG.
  final Uint8List? icon;

  /// App có sẵn của máy (YouTube, Chrome… trên nhiều máy cũng là app hệ thống).
  final bool isSystemApp;
}

/// Trạng thái các quyền khóa ứng dụng cần.
class AppLockPermissions {
  const AppLockPermissions({
    required this.accessibility,
    required this.exactAlarm,
    required this.batteryUnrestricted,
  });

  /// Dịch vụ Trợ năng của app_blocker đang bật (bắt buộc để chặn).
  final bool accessibility;

  /// Được đặt báo thức chính xác (bắt buộc để tự chặn lại sau khi mở tạm).
  final bool exactAlarm;

  /// Đã tắt tối ưu pin cho SafeFamily (nên có).
  final bool batteryUnrestricted;

  /// Đủ quyền bắt buộc.
  bool get ready => accessibility && exactAlarm;
}

enum AppLockSetting { accessibility, exactAlarm, battery, appDetails }

/// Lớp nói chuyện với Android (app_blocker + kênh riêng của SafeFamily).
abstract interface class AppLockPlatform {
  Future<List<InstalledApp>> installedApps();

  /// App đang bị chặn (không tính app đang mở tạm).
  Future<Set<String>> blockedApps();
  Future<void> block(List<String> packages);
  Future<void> unblock(List<String> packages);

  /// Hẹn tự chặn lại [packageName] lúc [at] (chạy cả khi SafeFamily đã tắt).
  Future<void> scheduleRelock(String packageName, DateTime at);
  Future<void> cancelRelock(String packageName);

  /// Package đang có lịch tự chặn lại.
  Future<Set<String>> scheduledRelocks();

  Future<AppLockPermissions> permissions();

  /// Package của app Điện thoại / Cài đặt / launcher trên máy này.
  Future<Set<String>> protectedPackages();

  Future<bool> openSetting(AppLockSetting setting);
}

class AppBlockerPlatform implements AppLockPlatform {
  AppBlockerPlatform({blocker.AppBlocker? appBlocker})
    : _blocker = appBlocker ?? blocker.AppBlocker.instance;

  static const _channel = MethodChannel('safefamily/app_lock');

  /// Lịch tự chặn lại do SafeFamily tạo: `<tiền tố><package>`.
  static const relockPrefix = 'safefamily-relock:';

  final blocker.AppBlocker _blocker;

  @override
  Future<List<InstalledApp>> installedApps() async => [
    for (final app in await _blocker.getApps())
      InstalledApp(
        packageName: app.packageName,
        name: app.appName,
        icon: app.icon,
        isSystemApp: app.isSystemApp,
      ),
  ];

  @override
  Future<Set<String>> blockedApps() async {
    final all = await _blocker.getBlockedApps();
    return {...all}..remove('__all__');
  }

  @override
  Future<void> block(List<String> packages) async {
    // Đặt lại chữ màn chặn mỗi lần chặn (sửa hằng số là có hiệu lực ngay).
    await _blocker.setBlockScreenConfig(
      const blocker.BlockScreenConfig(
        title: BlockScreenTexts.title,
        subtitle: BlockScreenTexts.subtitle,
        message: BlockScreenTexts.message,
        backgroundColor: Color(BlockScreenTexts.backgroundArgb),
      ),
    );
    await _blocker.blockApps(packages);
  }

  @override
  Future<void> unblock(List<String> packages) => _blocker.unblockApps(packages);

  /// Lịch MỘT LẦN: bắt đầu lúc [at], kết thúc 00:00 cùng ngày (đã qua) nên
  /// app_blocker không đặt báo thức kết thúc — báo thức kết thúc sẽ bỏ chặn.
  /// Tới giờ bắt đầu, app_blocker chặn lại dù SafeFamily đã tắt.
  ///
  /// Mỗi lần SafeFamily mở, app_blocker xóa các lịch "đã qua giờ kết thúc"
  /// này → [AppLockController] đặt lại.
  @override
  Future<void> scheduleRelock(String packageName, DateTime at) async {
    await cancelRelock(packageName);
    await _blocker.addSchedule(
      blocker.BlockSchedule(
        id: '$relockPrefix$packageName',
        name: 'SafeFamily: chặn lại $packageName',
        appIdentifiers: [packageName],
        scheduleDate: DateTime(at.year, at.month, at.day),
        startTime: TimeOfDay(hour: at.hour, minute: at.minute),
        endTime: const TimeOfDay(hour: 0, minute: 0),
      ),
    );
  }

  @override
  Future<void> cancelRelock(String packageName) =>
      _blocker.removeSchedule('$relockPrefix$packageName');

  @override
  Future<Set<String>> scheduledRelocks() async => {
    for (final schedule in await _blocker.getSchedules())
      if (schedule.id.startsWith(relockPrefix))
        schedule.id.substring(relockPrefix.length),
  };

  @override
  Future<AppLockPermissions> permissions() async {
    final map = await _channel.invokeMapMethod<String, bool>('permissions');
    return AppLockPermissions(
      accessibility: map?['accessibility'] ?? false,
      exactAlarm: map?['exactAlarm'] ?? false,
      batteryUnrestricted: map?['battery'] ?? false,
    );
  }

  @override
  Future<Set<String>> protectedPackages() async => {
    ...?await _channel.invokeListMethod<String>('protectedPackages'),
  };

  @override
  Future<bool> openSetting(AppLockSetting setting) async {
    const package = 'package:${AppInfo.applicationId}';
    return switch (setting) {
      AppLockSetting.accessibility => _launch(
        const AndroidIntent(action: 'android.settings.ACCESSIBILITY_SETTINGS'),
      ),
      AppLockSetting.exactAlarm => _launch(
        const AndroidIntent(
          action: 'android.settings.REQUEST_SCHEDULE_EXACT_ALARM',
          data: package,
        ),
      ),
      AppLockSetting.battery =>
        await _launch(
              const AndroidIntent(
                action: 'android.settings.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
                data: package,
              ),
            ) ||
            await _launch(
              const AndroidIntent(
                action: 'android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS',
              ),
            ),
      AppLockSetting.appDetails =>
        const AndroidSystemSettings().openAppSettings(),
    };
  }

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
