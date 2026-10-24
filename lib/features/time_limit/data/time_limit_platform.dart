import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../core/security/device_guard.dart';
import '../../report/domain/usage_report.dart';
import '../domain/time_limit_config.dart';

/// Thời gian đã dùng hôm nay (phút).
class UsageToday {
  const UsageToday({required this.totalMinutes, this.apps = const {}});

  final int totalMinutes;
  final Map<String, int> apps;
}

/// Trạng thái chạy của giờ học (native giữ, không nằm trong cấu hình).
class StudyStatus {
  const StudyStatus({
    this.active = false,
    this.sessionMinutesLeft = 0,
    this.disabledToday = false,
  });

  /// Giờ học đang hiệu lực lúc này.
  final bool active;

  /// Phiên "bắt đầu ngay" còn bao nhiêu phút (0 = không có phiên).
  final int sessionMinutesLeft;

  /// Đã "tắt hôm nay" (lịch giờ học nghỉ đến hết ngày).
  final bool disabledToday;
}

/// Lớp nói chuyện với Android cho giới hạn thời gian (kênh `safefamily/time_limit`).
abstract interface class TimeLimitPlatform {
  Future<TimeLimitConfig> load();
  Future<void> save(TimeLimitConfig config);

  /// Đã cấp quyền "Truy cập dữ liệu sử dụng" chưa.
  Future<bool> hasUsageAccess();
  Future<void> openUsageAccess();

  /// `null` nếu chưa có quyền hoặc không đọc được.
  Future<UsageToday?> usageToday();

  /// Số phút đã thêm cho hôm nay (về 0 lúc nửa đêm).
  Future<int> bonusMinutes();

  /// Báo cáo [days] ngày gần nhất (cũ nhất trước, cuối là hôm nay);
  /// `null` nếu chưa có quyền hoặc không đọc được.
  Future<List<DayUsage>?> usageReport(int days);

  /// Tên hiển thị của các gói (nhãn app trong hệ thống).
  Future<Map<String, String>> appLabels(List<String> packages);

  /// Cộng [minutes] vào hạn mức hôm nay; trả về tổng giờ thêm hôm nay.
  Future<int> addBonus(int minutes);

  Future<StudyStatus> studyStatus();

  /// Bắt đầu giờ học ngay trong [minutes] phút, bất kể lịch.
  Future<void> startStudy(int minutes);
  Future<void> stopStudy();

  /// Tắt (hoặc bật lại) lịch giờ học đến hết hôm nay.
  Future<void> setStudyDisabledToday(bool disabled);

  /// Tạm dừng máy còn bao nhiêu phút: 0 = không tạm dừng,
  /// [pauseUntilOff] = đến khi phụ huynh tắt.
  Future<int> pauseMinutesLeft();

  /// Tạm dừng máy [minutes] phút; 0 = đến khi tắt.
  Future<void> startPause(int minutes);
  Future<void> stopPause();
}

/// Giá trị [TimeLimitPlatform.pauseMinutesLeft] khi tạm dừng đến khi tắt.
const pauseUntilOff = 0x7fffffff;

class MethodChannelTimeLimit implements TimeLimitPlatform {
  const MethodChannelTimeLimit({this.guard = const MethodChannelDeviceGuard()});

  static const _channel = MethodChannel('safefamily/time_limit');

  final DeviceGuardPlatform guard;

  @override
  Future<TimeLimitConfig> load() async {
    try {
      final json = await _channel.invokeMethod<String>('config');
      return json == null ? TimeLimitConfig() : TimeLimitConfig.fromJson(json);
    } on PlatformException catch (error) {
      debugPrint('Giới hạn thời gian: không đọc được cấu hình ($error)');
      return TimeLimitConfig();
    }
  }

  @override
  Future<void> save(TimeLimitConfig config) =>
      _channel.invokeMethod<void>('setConfig', config.toJson());

  @override
  Future<bool> hasUsageAccess() async {
    try {
      return await _channel.invokeMethod<bool>('usageAccess') ?? false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> openUsageAccess() async {
    // Trang này liệt kê "SafeFamily" nên dịch vụ bảo vệ sẽ hỏi PIN nếu không mở cửa trước.
    await guard.allowSettings(settingsAllowSeconds);
    await _channel.invokeMethod<void>('openUsageAccess');
  }

  @override
  Future<UsageToday?> usageToday() async {
    try {
      final map = await _channel.invokeMapMethod<String, Object?>('usageToday');
      if (map == null) return null;
      final apps = (map['apps'] as Map?) ?? const {};
      return UsageToday(
        totalMinutes: (map['totalMinutes'] as num?)?.toInt() ?? 0,
        apps: {
          for (final e in apps.entries)
            e.key as String: (e.value as num).toInt(),
        },
      );
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<List<DayUsage>?> usageReport(int days) async {
    try {
      final raw = await _channel.invokeListMethod<Object?>('usageReport', days);
      if (raw == null) return null;
      return [for (final item in raw) ?DayUsage.fromMap(item)];
    } on Object catch (error) {
      debugPrint('Báo cáo: không đọc được ($error)');
      return null;
    }
  }

  @override
  Future<Map<String, String>> appLabels(List<String> packages) async {
    try {
      final map = await _channel.invokeMapMethod<String, String>(
        'appLabels',
        packages,
      );
      return map ?? const {};
    } on Object {
      return const {};
    }
  }

  @override
  Future<int> bonusMinutes() async {
    try {
      return await _channel.invokeMethod<int>('bonusMinutes') ?? 0;
    } on PlatformException {
      return 0;
    }
  }

  @override
  Future<int> addBonus(int minutes) async =>
      await _channel.invokeMethod<int>('addBonus', minutes) ?? 0;

  @override
  Future<StudyStatus> studyStatus() async {
    try {
      final map = await _channel.invokeMapMethod<String, Object?>(
        'studyStatus',
      );
      if (map == null) return const StudyStatus();
      return StudyStatus(
        active: map['active'] == true,
        sessionMinutesLeft: (map['sessionMinutesLeft'] as num?)?.toInt() ?? 0,
        disabledToday: map['disabledToday'] == true,
      );
    } on PlatformException {
      return const StudyStatus();
    }
  }

  @override
  Future<void> startStudy(int minutes) =>
      _channel.invokeMethod<void>('startStudy', minutes);

  @override
  Future<void> stopStudy() => _channel.invokeMethod<void>('stopStudy');

  @override
  Future<void> setStudyDisabledToday(bool disabled) =>
      _channel.invokeMethod<void>('setStudyDisabledToday', disabled);

  @override
  Future<int> pauseMinutesLeft() async {
    try {
      return await _channel.invokeMethod<int>('pauseStatus') ?? 0;
    } on Object {
      return 0;
    }
  }

  @override
  Future<void> startPause(int minutes) =>
      _channel.invokeMethod<void>('startPause', minutes);

  @override
  Future<void> stopPause() => _channel.invokeMethod<void>('stopPause');
}
