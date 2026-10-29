import 'package:flutter_test/flutter_test.dart';
import 'package:safe_family_app/app/feature_registry.dart';
import 'package:safe_family_app/core/security/device_guard.dart';
import 'package:safe_family_app/features/time_limit/data/time_limit_platform.dart';
import 'package:safe_family_app/features/time_limit/domain/time_limit_config.dart';

class _Platform implements TimeLimitPlatform {
  TimeLimitConfig config = TimeLimitConfig();
  StudyStatus study = const StudyStatus();
  int pause = 0;
  DateTime? limitOff;
  bool stoppedStudy = false;

  @override
  Future<TimeLimitConfig> load() async => config;
  @override
  Future<void> save(TimeLimitConfig c) async => config = c;
  @override
  Future<StudyStatus> studyStatus() async => study;
  @override
  Future<int> pauseMinutesLeft() async => pause;
  @override
  Future<void> stopPause() async => pause = 0;
  @override
  Future<void> stopStudy() async => stoppedStudy = true;
  @override
  Future<DateTime?> totalLimitDisabledUntil() async => limitOff;
  @override
  Future<void> setTotalLimitDisabledToday(bool disabled) async =>
      limitOff = disabled ? DateTime(2030) : null;

  @override
  dynamic noSuchMethod(Invocation invocation) async {}
}

void main() {
  // Thứ Tư 2026-10-28 22:00
  final now = DateTime(2026, 10, 28, 22);
  late _Platform platform;
  late FeatureRegistry registry;

  setUp(() {
    platform = _Platform();
    registry = FeatureRegistry(
      timeLimit: platform,
      deviceGuard: const NoDeviceGuard(),
      clock: () => now,
    );
  });

  Future<Map<String, RestrictionFeature>> byId() async => {
    for (final f in await registry.snapshot()) f.id: f,
  };

  test('không có gì chạy thì danh sách active rỗng', () async {
    expect(await registry.activeFeatures(), isEmpty);
  });

  test('tạm dừng có hẹn giờ trả về endsAt, "đến khi tắt" thì null', () async {
    platform.pause = 30;
    var pause = (await byId())['pause']!;
    expect(pause.isActive, isTrue);
    expect(pause.endsAt, now.add(const Duration(minutes: 30)));

    platform.pause = pauseUntilOff;
    pause = (await byId())['pause']!;
    expect(pause.isActive, isTrue);
    expect(pause.endsAt, isNull);
  });

  test('giờ ngủ qua nửa đêm kết thúc sáng hôm sau', () async {
    platform.config = TimeLimitConfig(
      bedtimeEnabled: true,
      bedtime: List.filled(7, defaultBedtime),
    );
    final bed = (await byId())['bedtime']!;
    expect(bed.isActive, isTrue);
    expect(bed.endsAt, DateTime(2026, 10, 29, 6));
  });

  test('giờ học theo phiên lấy endsAt từ phút còn lại', () async {
    platform.study = const StudyStatus(active: true, sessionMinutesLeft: 45);
    final study = (await byId())['study']!;
    expect(study.endsAt, now.add(const Duration(minutes: 45)));
  });

  test('disable() tắt tính năng và tính năng hết active', () async {
    platform.pause = 10;
    platform.config = TimeLimitConfig(enabled: true, total: List.filled(7, 60));
    var features = await byId();
    expect(features['total_limit']!.isActive, isTrue);

    expect(await features['pause']!.disable!((_) async => true), isTrue);
    expect(await features['total_limit']!.disable!((_) async => true), isTrue);

    features = await byId();
    expect(features['pause']!.isActive, isFalse);
    expect(features['total_limit']!.isActive, isFalse);
  });

  test('tắt giờ học: dừng phiên và tắt lịch', () async {
    platform.config = TimeLimitConfig(studyEnabled: true);
    platform.study = const StudyStatus(active: true, sessionMinutesLeft: 5);
    await (await byId())['study']!.disable!((_) async => true);
    expect(platform.stoppedStudy, isTrue);
    expect(platform.config.studyEnabled, isFalse);
  });

  test('currentWindowEnd: ngoài khung trả về null', () {
    final week = List<BedtimeWindow?>.filled(7, defaultStudy);
    expect(currentWindowEnd(week, DateTime(2026, 10, 28, 12)), isNull);
    expect(
      currentWindowEnd(week, DateTime(2026, 10, 28, 19, 30)),
      DateTime(2026, 10, 28, 21),
    );
  });
}
