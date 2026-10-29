import '../core/security/device_guard.dart';
import '../core/security/parent_guard.dart';
import '../features/app_lock/presentation/app_lock_controller.dart';
import '../features/time_limit/data/time_limit_platform.dart';
import '../features/time_limit/domain/time_limit_config.dart';

/// Một tính năng có thể cản trở việc dùng máy bình thường.
///
/// Không giữ state riêng: [FeatureRegistry.snapshot] đọc lại từ nguồn sẵn có
/// của từng tính năng mỗi lần gọi.
class RestrictionFeature {
  const RestrictionFeature({
    required this.id,
    required this.name,
    required this.isActive,
    this.endsAt,
    this.disable,
    this.settingsIntent,
  });

  final String id;
  final String name;

  /// Đang cản trở lúc này.
  final bool isActive;

  /// Lúc tự hết; `null` = không hẹn giờ (chạy đến khi phụ huynh tắt).
  final DateTime? endsAt;

  /// Tắt ngay trong app, đã gồm xác thực phụ huynh. `true` = đã tắt, `false` =
  /// phụ huynh hủy. `null` = không tắt được trong app.
  final Future<bool> Function(PinPrompt promptPin)? disable;

  /// Action Android mở trang Cài đặt để tắt (khi [disable] là `null`).
  final String? settingsIntent;
}

/// Gom các tính năng cản trở dùng máy về một chỗ cho màn "Đang cản trở".
class FeatureRegistry {
  FeatureRegistry({
    required this.timeLimit,
    required this.deviceGuard,
    this.appLock,
    this.parentGuard,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final TimeLimitPlatform timeLimit;
  final DeviceGuardPlatform deviceGuard;
  final AppLockController? appLock;

  /// `null` (test, chưa đặt khóa) thì bỏ qua xác thực.
  final ParentGuard? parentGuard;
  final DateTime Function() _clock;

  /// Mọi tính năng đã đăng ký, kể cả cái đang không chạy.
  Future<List<RestrictionFeature>> snapshot() async {
    final now = _clock();
    final config = await timeLimit.load();
    final study = await timeLimit.studyStatus();
    final limitOff = await timeLimit.totalLimitDisabledUntil();
    final pauseLeft = await timeLimit.pauseMinutesLeft();
    final device = await deviceGuard.status();
    final guard = parentGuard;
    final lock = appLock;

    final limitToday = config.totalFor(now.weekday);
    final inBedtime = config.inBedtime(now);

    return [
      RestrictionFeature(
        id: 'pause',
        name: 'Tạm dừng máy',
        isActive: pauseLeft > 0,
        endsAt: pauseLeft > 0 && pauseLeft != pauseUntilOff
            ? now.add(Duration(minutes: pauseLeft))
            : null,
        disable: _guarded('Tắt tạm dừng máy', timeLimit.stopPause),
      ),
      RestrictionFeature(
        id: 'study',
        name: 'Giờ học',
        isActive: study.active,
        endsAt: !study.active
            ? null
            : study.sessionMinutesLeft > 0
            ? now.add(Duration(minutes: study.sessionMinutesLeft))
            : currentWindowEnd(config.study, now),
        // Giống nút tắt trên màn Giới hạn: dừng phiên + tắt lịch.
        disable: _guarded('Tắt giờ học', () async {
          await timeLimit.stopStudy();
          await timeLimit.save(config.copyWith(studyEnabled: false));
        }),
      ),
      RestrictionFeature(
        id: 'bedtime',
        name: 'Giờ ngủ',
        isActive: inBedtime,
        endsAt: inBedtime ? currentWindowEnd(config.bedtime, now) : null,
        disable: _guarded(
          'Tắt giờ ngủ',
          () => timeLimit.save(config.copyWith(bedtimeEnabled: false)),
        ),
      ),
      RestrictionFeature(
        id: 'total_limit',
        name: 'Giới hạn thời gian dùng máy',
        isActive: config.enabled && limitToday != null && limitOff == null,
        // Tắt đến hết hôm nay (cùng nút "Tắt giới hạn cả ngày").
        disable: _guarded(
          'Tắt giới hạn cả ngày hôm nay',
          () => timeLimit.setTotalLimitDisabledToday(true),
        ),
      ),
      RestrictionFeature(
        id: 'app_lock',
        name: 'Khóa ứng dụng',
        isActive: lock != null && lock.lockedPackages.isNotEmpty,
        disable: lock == null
            ? null
            : _guarded('Bỏ chặn mọi ứng dụng', () async {
                for (final package in [...lock.lockedPackages]) {
                  await lock.setLocked(package, false);
                }
              }),
      ),
      RestrictionFeature(
        id: 'child_mode',
        name: 'Chế độ trẻ em',
        isActive: guard?.childMode ?? false,
        // setChildMode(false) tự xác thực, không bọc thêm lần nữa.
        disable: guard == null
            ? null
            : (promptPin) => guard.setChildMode(false, promptPin: promptPin),
      ),
      RestrictionFeature(
        id: 'settings_guard',
        name: 'Bảo vệ màn Cài đặt',
        isActive: device.settingsGuard,
        // TODO(verify): T0.1 sẽ thay bằng PermissionRegistry.
        settingsIntent: 'android.settings.ACCESSIBILITY_SETTINGS',
      ),
      RestrictionFeature(
        id: 'anti_uninstall',
        name: 'Chống gỡ ứng dụng',
        isActive: device.deviceAdmin,
        // TODO(verify): T0.1 sẽ tắt thẳng bằng removeActiveAdmin().
        settingsIntent: 'android.settings.SECURITY_SETTINGS',
      ),
    ];
  }

  /// Chỉ những tính năng đang cản trở.
  Future<List<RestrictionFeature>> activeFeatures() async => [
    for (final f in await snapshot())
      if (f.isActive) f,
  ];

  /// Bọc [run] bằng xác thực phụ huynh (bỏ qua khi chưa có [parentGuard]).
  Future<bool> Function(PinPrompt) _guarded(
    String action,
    Future<void> Function() run,
  ) => (promptPin) async {
    final guard = parentGuard;
    if (guard != null && !await guard.require(action, promptPin: promptPin)) {
      return false;
    }
    await run();
    return true;
  };
}

/// Lúc kết thúc khung giờ của [week] đang chứa [at]; `null` nếu [at] không
/// nằm trong khung nào. Cùng quy tắc với `inWeekWindow`.
DateTime? currentWindowEnd(List<BedtimeWindow?> week, DateTime at) {
  DateTime endOf(BedtimeWindow w, int dayOffset) => DateTime(
    at.year,
    at.month,
    at.day + dayOffset,
    w.endMinute ~/ 60,
    w.endMinute % 60,
  );

  final minute = at.hour * 60 + at.minute;
  final today = week[at.weekday - 1];
  if (today != null) {
    final inside = today.overnight
        ? minute >= today.startMinute
        : minute >= today.startMinute && minute < today.endMinute;
    if (inside) return endOf(today, today.overnight ? 1 : 0);
  }
  final yesterday = week[(at.weekday + 5) % 7];
  if (yesterday != null &&
      yesterday.overnight &&
      minute < yesterday.endMinute) {
    return endOf(yesterday, 0);
  }
  return null;
}
