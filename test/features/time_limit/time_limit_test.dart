import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safe_family_app/core/theme/app_theme.dart';
import 'package:safe_family_app/features/app_lock/data/app_lock_platform.dart';
import 'package:safe_family_app/features/report/domain/usage_report.dart';
import 'package:safe_family_app/features/time_limit/data/time_limit_platform.dart';
import 'package:safe_family_app/features/time_limit/domain/time_limit_config.dart';
import 'package:safe_family_app/features/time_limit/presentation/time_limit_page.dart';

class _FakePlatform implements TimeLimitPlatform {
  TimeLimitConfig config = TimeLimitConfig();
  bool access = true;

  @override
  Future<TimeLimitConfig> load() async => config;

  @override
  Future<void> save(TimeLimitConfig c) async => config = c;

  @override
  Future<bool> hasUsageAccess() async => access;

  @override
  Future<void> openUsageAccess() async {}

  @override
  Future<UsageToday?> usageToday() async =>
      access ? const UsageToday(totalMinutes: 80) : null;

  @override
  Future<List<DayUsage>?> usageReport(int days) async => null;

  @override
  Future<Map<String, String>> appLabels(List<String> packages) async => {};

  int bonus = 0;

  @override
  Future<int> bonusMinutes() async => bonus;

  @override
  Future<int> addBonus(int minutes) async => bonus += minutes;

  StudyStatus study = const StudyStatus();
  int? startedStudy;
  bool? disabledToday;

  @override
  Future<StudyStatus> studyStatus() async => study;

  @override
  Future<void> startStudy(int minutes) async => startedStudy = minutes;

  @override
  Future<void> stopStudy() async {}

  @override
  Future<void> setStudyDisabledToday(bool disabled) async =>
      disabledToday = disabled;

  int pauseLeft = 0;

  @override
  Future<int> pauseMinutesLeft() async => pauseLeft;

  @override
  Future<void> startPause(int minutes) async =>
      pauseLeft = minutes == 0 ? pauseUntilOff : minutes;

  @override
  Future<void> stopPause() async => pauseLeft = 0;
}

void main() {
  test('JSON khứ hồi, null <-> -1, tuần thiếu ngày thì bù không giới hạn', () {
    final config = TimeLimitConfig(
      enabled: true,
      total: [60, null, 30, null, null, null, 120],
      apps: {
        'com.google.android.youtube': [2, ...List<int?>.filled(6, null)],
      },
    );
    expect(config.toJson(), contains('"total":[60,-1,30,-1,-1,-1,120]'));
    final back = TimeLimitConfig.fromJson(config.toJson());
    expect(back.enabled, isTrue);
    expect(back.total, config.total);
    expect(back.appLimitFor('com.google.android.youtube', 1), 2);
    expect(back.totalFor(2), isNull);

    final short = TimeLimitConfig.fromJson('{"enabled":true,"total":[5]}');
    expect(short.total, [5, null, null, null, null, null, null]);
    expect(TimeLimitConfig.fromJson('hỏng').enabled, isFalse);
  });

  test('giờ ngủ qua nửa đêm: 23:30 và 05:30 bị chặn, 06:01 thì không', () {
    // 2026-10-26 là Thứ Hai.
    final config = TimeLimitConfig(
      bedtimeEnabled: true,
      bedtime: [defaultBedtime, ...List<BedtimeWindow?>.filled(6, null)],
    );
    expect(config.inBedtime(DateTime(2026, 10, 26, 23, 30)), isTrue);
    expect(config.inBedtime(DateTime(2026, 10, 26, 20, 59)), isFalse);
    expect(
      config.inBedtime(DateTime(2026, 10, 26, 5, 30)),
      isFalse,
    ); // CN trước không có khung
    expect(
      config.inBedtime(DateTime(2026, 10, 27, 5, 30)),
      isTrue,
    ); // sáng Thứ Ba
    expect(config.inBedtime(DateTime(2026, 10, 27, 5, 59)), isTrue);
    expect(config.inBedtime(DateTime(2026, 10, 27, 6, 1)), isFalse);
    expect(
      config
          .copyWith(bedtimeEnabled: false)
          .inBedtime(DateTime(2026, 10, 26, 23)),
      isFalse,
    );
  });

  test('giờ học: lịch trong ngày, JSON khứ hồi, danh sách trắng', () {
    final config = TimeLimitConfig(
      studyEnabled: true,
      study: [defaultStudy, ...List<BedtimeWindow?>.filled(6, null)],
      studyApps: {'com.duolingo', 'com.khanacademy'},
    );
    expect(config.inStudy(DateTime(2026, 10, 26, 18, 59)), isFalse);
    expect(config.inStudy(DateTime(2026, 10, 26, 19, 0)), isTrue);
    expect(config.inStudy(DateTime(2026, 10, 26, 20, 59)), isTrue);
    expect(config.inStudy(DateTime(2026, 10, 26, 21, 0)), isFalse);
    expect(config.inStudy(DateTime(2026, 10, 27, 19, 30)), isFalse);
    expect(
      config
          .copyWith(studyEnabled: false)
          .inStudy(DateTime(2026, 10, 26, 19, 30)),
      isFalse,
    );
    expect(config.studyAllows('com.duolingo'), isTrue);
    expect(config.studyAllows('com.google.android.youtube'), isFalse);

    final back = TimeLimitConfig.fromJson(config.toJson());
    expect(back.studyEnabled, isTrue);
    expect(back.study, config.study);
    expect(back.studyApps, config.studyApps);
    // Cấu hình cũ chưa có mục study vẫn đọc được.
    final old = TimeLimitConfig.fromJson('{"enabled":true}');
    expect(old.studyEnabled, isFalse);
    expect(old.studyApps, isEmpty);
  });

  test('giờ ngủ trong cùng ngày, và JSON khứ hồi', () {
    final config = TimeLimitConfig(
      bedtimeEnabled: true,
      bedtime: [
        const BedtimeWindow(13 * 60, 14 * 60),
        ...List<BedtimeWindow?>.filled(6, null),
      ],
    );
    expect(config.inBedtime(DateTime(2026, 10, 26, 13, 0)), isTrue);
    expect(config.inBedtime(DateTime(2026, 10, 26, 14, 0)), isFalse);
    final back = TimeLimitConfig.fromJson(config.toJson());
    expect(back.bedtimeEnabled, isTrue);
    expect(back.bedtime, config.bedtime);
    expect(formatClock(21 * 60 + 5), '21:05');
    // Khung hỏng bị bỏ qua thay vì làm hỏng cả cấu hình.
    final bad = TimeLimitConfig.fromJson(
      '{"bedtime":{"enabled":true,"days":[[5000,1],"x"]}}',
    );
    expect(bad.bedtime.every((w) => w == null), isTrue);
  });

  test('formatMinutes', () {
    expect(formatMinutes(0), '0 phút');
    expect(formatMinutes(45), '45 phút');
    expect(formatMinutes(60), '1 giờ');
    expect(formatMinutes(80), '1 giờ 20 phút');
  });

  testWidgets('bật giới hạn, đặt tổng thứ Hai, thêm app, hiện đã dùng', (
    tester,
  ) async {
    final platform = _FakePlatform();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: TimeLimitPage(
          platform: platform,
          loadApps: () async => const [
            InstalledApp(
              packageName: 'com.google.android.youtube',
              name: 'YouTube',
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Hôm nay con đã dùng 1 giờ 20 phút.'), findsOneWidget);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(platform.config.enabled, isTrue);

    await tester.tap(find.byType(Switch).at(1)); // công tắc Thứ Hai
    await tester.pumpAndSettle();
    expect(platform.config.totalFor(1), 60);

    await tester.scrollUntilVisible(find.text('Thêm ứng dụng'), 300);
    await tester.tap(find.text('Thêm ứng dụng'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('YouTube'));
    await tester.pumpAndSettle();
    expect(platform.config.apps.keys, ['com.google.android.youtube']);
  });

  testWidgets('thiếu quyền: hiện cảnh báo', (tester) async {
    final platform = _FakePlatform()..access = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: TimeLimitPage(platform: platform, loadApps: () async => const []),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Chưa cấp quyền đo thời gian dùng'), findsOneWidget);
  });

  testWidgets('thêm giờ: chọn 15 phút thì cộng vào giờ thêm hôm nay', (
    tester,
  ) async {
    final platform = _FakePlatform();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: TimeLimitPage(platform: platform, loadApps: () async => const []),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thêm giờ'));
    await tester.pumpAndSettle();
    expect(find.text('Thêm 5 phút'), findsOneWidget);
    expect(find.text('Thêm 30 phút'), findsOneWidget);
    await tester.tap(find.text('Thêm 15 phút'));
    await tester.pumpAndSettle();
    expect(platform.bonus, 15);
    expect(find.text('Hôm nay đã thêm 15 phút.'), findsOneWidget);
  });

  testWidgets('giờ học: bắt đầu ngay 30 phút và tắt hôm nay', (tester) async {
    final platform = _FakePlatform()
      ..config = TimeLimitConfig(studyEnabled: true);
    await tester.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: TimeLimitPage(platform: platform, loadApps: () async => const []),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Bắt đầu giờ học ngay'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('30 phút'));
    await tester.pumpAndSettle();
    expect(platform.startedStudy, 30);

    await tester.tap(find.text('Tắt hôm nay'));
    await tester.pumpAndSettle();
    expect(platform.disabledToday, isTrue);
  });
}
