import 'dart:convert';

import '../../../core/network/api_client.dart';
import '../../../core/network/policy_sync.dart';
import '../../report/domain/usage_report.dart';
import '../domain/time_limit_config.dart';
import 'time_limit_platform.dart';

/// Giới hạn thời gian của MÁY CON, thao tác từ máy mẹ: cấu hình đọc / ghi vào luật
/// của máy con trên server, số liệu đọc từ báo cáo máy con gửi lên, việc cần làm
/// ngay (giờ học, thêm giờ, tắt giới hạn hôm nay) gửi thành lệnh. Máy mẹ không
/// lưu hay thi hành gì trên chính nó.
class RemoteTimeLimitPlatform implements TimeLimitPlatform {
  RemoteTimeLimitPlatform({
    required this.api,
    required this.sync,
    required this.childId,
  });

  final ApiClient api;
  final PolicySync sync;
  final int childId;

  /// Số phút mẹ đã cộng thêm trong lần mở màn này (máy con không báo lại số này).
  int _added = 0;

  @override
  Future<TimeLimitConfig> load() async {
    final json = PolicySync.timeLimitIn((await api.getPolicy(childId)).json);
    return json == null ? TimeLimitConfig() : TimeLimitConfig.fromJson(json);
  }

  @override
  Future<void> save(TimeLimitConfig config) =>
      sync.setTimeLimit(childId, config.toJson());

  /// Quyền "Truy cập dữ liệu sử dụng" là của máy con; thiếu thì máy con báo trong trạng thái.
  @override
  Future<bool> hasUsageAccess() async => true;

  @override
  Future<void> openUsageAccess() async {}

  @override
  Future<UsageToday?> usageToday() async {
    final now = DateTime.now();
    try {
      final days = await api.getDeviceUsage(childId, from: now, to: now);
      if (days.isEmpty) return const UsageToday(totalMinutes: 0);
      final today = days.last;
      return UsageToday(totalMinutes: today.totalMinutes, apps: today.apps);
    } on ApiException {
      return null;
    }
  }

  @override
  Future<int> bonusMinutes() async => _added;

  @override
  Future<List<DayUsage>?> usageReport(int days) async => null;

  @override
  Future<Map<String, String>> appLabels(List<String> packages) async {
    try {
      final apps = await api.getDeviceApps(childId);
      return {for (final a in apps) a.packageName: a.label};
    } on ApiException {
      return {};
    }
  }

  @override
  Future<int> addBonus(int minutes) async {
    await api.sendCommand(
      childId,
      'extra_time_grant',
      payloadJson: jsonEncode({'minutes': minutes}),
    );
    return _added += minutes;
  }

  @override
  Future<StudyStatus> studyStatus() async {
    try {
      final status = await api.getDeviceStatus(childId);
      return StudyStatus(active: status.studyActive);
    } on ApiException {
      return const StudyStatus();
    }
  }

  @override
  Future<void> startStudy(int minutes) => api.sendCommand(
    childId,
    'study_start',
    payloadJson: jsonEncode({'minutes': minutes}),
  );

  @override
  Future<void> stopStudy() => api.sendCommand(childId, 'study_stop');

  /// Máy con chưa có lệnh "tắt lịch giờ học hôm nay"; sửa lịch giờ học trong cấu hình thay thế.
  @override
  Future<void> setStudyDisabledToday(bool disabled) =>
      throw UnsupportedError('Chưa hỗ trợ tắt lịch giờ học hôm nay từ xa.');

  @override
  Future<DateTime?> totalLimitDisabledUntil() async => null;

  @override
  Future<void> setTotalLimitDisabledToday(bool disabled) => api.sendCommand(
    childId,
    disabled ? 'disable_limit_today' : 'enable_limit_today',
  );

  @override
  Future<int> pauseMinutesLeft() async {
    try {
      final status = await api.getDeviceStatus(childId);
      return status.isPaused ? pauseUntilOff : 0;
    } on ApiException {
      return 0;
    }
  }

  @override
  Future<void> startPause(int minutes) => api.sendCommand(
    childId,
    'pause',
    payloadJson: jsonEncode({'minutes': minutes}),
  );

  @override
  Future<void> stopPause() => api.sendCommand(childId, 'unpause');
}
