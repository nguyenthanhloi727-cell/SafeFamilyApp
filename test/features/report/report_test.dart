import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safe_family_app/core/security/unlock_log.dart';
import 'package:safe_family_app/core/theme/app_theme.dart';
import 'package:safe_family_app/features/report/domain/usage_report.dart';
import 'package:safe_family_app/features/report/presentation/report_page.dart';
import 'package:safe_family_app/features/time_limit/data/time_limit_platform.dart';
import 'package:safe_family_app/features/time_limit/domain/time_limit_config.dart';

class _Platform implements TimeLimitPlatform {
  _Platform(this.days);

  final List<DayUsage>? days;

  @override
  Future<List<DayUsage>?> usageReport(int n) async => days;

  @override
  Future<Map<String, String>> appLabels(List<String> packages) async => {
    for (final p in packages) p: 'Nhãn $p',
  };

  @override
  Future<TimeLimitConfig> load() async => TimeLimitConfig(
    enabled: true,
    total: [120, 120, 120, 120, 120, 120, 120],
  );

  @override
  Future<int> bonusMinutes() async => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) async {}
}

List<DayUsage> _week() => [
  for (var i = 0; i < 7; i++)
    DayUsage(
      date: DateTime(2026, 10, 18 + i),
      totalMinutes: 30 + i * 10,
      blocks: i == 6 ? 3 : 0,
      apps: {'com.youtube': 20 + i, 'com.game': 10 + i},
    ),
];

void main() {
  test('DayUsage.fromMap đọc ngày, phút, số lần chặn; hỏng thì null', () {
    final day = DayUsage.fromMap({
      'date': '2026-10-24',
      'totalMinutes': 80,
      'blocks': 2,
      'apps': {'a': 50, 'b': 30},
    });
    expect(day!.date, DateTime(2026, 10, 24));
    expect(day.totalMinutes, 80);
    expect(day.blocks, 2);
    expect(day.apps['a'], 50);
    expect(DayUsage.fromMap({'date': 'x'}), isNull);
    expect(DayUsage.fromMap(null), isNull);
  });

  test('topApps cộng dồn, sắp giảm dần, cắt 5, bỏ app 0 phút', () {
    final days = [
      DayUsage(
        date: DateTime(2026, 10, 23),
        totalMinutes: 0,
        apps: {'a': 10, 'b': 50, 'c': 5, 'd': 6, 'e': 7, 'f': 8, 'z': 0},
      ),
      DayUsage(date: DateTime(2026, 10, 24), totalMinutes: 0, apps: {'a': 60}),
    ];
    final top = topApps(days);
    expect([for (final t in top) t.packageName], ['a', 'b', 'f', 'e', 'd']);
    expect(top.first.minutes, 70);
  });

  test('todaySummary: còn bao lâu, đã hết giờ, không hạn mức, có giờ thêm', () {
    expect(
      todaySummary(80, limitMinutes: 120),
      'Hôm nay con dùng 1 giờ 20 phút, còn 40 phút',
    );
    expect(todaySummary(120, limitMinutes: 120), endsWith('đã hết giờ'));
    expect(todaySummary(45), 'Hôm nay con dùng 45 phút');
    expect(
      todaySummary(120, limitMinutes: 120, bonusMinutes: 15),
      endsWith('còn 15 phút'),
    );
  });

  test('totalLimitFor theo thứ, null khi tắt', () {
    final config = TimeLimitConfig(
      enabled: true,
      total: [null, null, null, null, null, null, 90],
    );
    expect(totalLimitFor(config, DateTime(2026, 10, 25)), 90); // Chủ Nhật
    expect(totalLimitFor(config, DateTime(2026, 10, 24)), isNull);
    expect(totalLimitFor(TimeLimitConfig(), DateTime(2026, 10, 25)), isNull);
  });

  test('unlockCounts chỉ tính 7 ngày, bỏ hệ thống và đã hủy', () {
    final now = DateTime(2026, 10, 24, 12);
    UnlockLogEntry e(
      DateTime t,
      UnlockResult r, [
      UnlockMethod m = UnlockMethod.pin,
    ]) => UnlockLogEntry(time: t, action: 'x', method: m, result: r);
    final counts = unlockCounts([
      e(now, UnlockResult.success),
      e(now, UnlockResult.failure),
      e(now, UnlockResult.canceled),
      e(now, UnlockResult.failure, UnlockMethod.system),
      e(DateTime(2026, 10, 18, 23), UnlockResult.success), // ngày thứ 7
      e(DateTime(2026, 10, 17, 23), UnlockResult.success), // quá cũ
    ], now);
    expect(counts.success, 2);
    expect(counts.failure, 1);
  });

  testWidgets('ReportPage hiện hôm nay, top app và số lần chặn', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ReportPage(
          platform: _Platform(_week()),
          loadApps: () async => [],
          now: () => DateTime(2026, 10, 24, 12),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 giờ 30 phút'), findsWidgets);
    expect(find.text('Nhãn com.youtube'), findsOneWidget);
    expect(find.textContaining('chạm vào app bị chặn 3 lần'), findsOneWidget);
    expect(find.textContaining('còn 30 phút'), findsOneWidget);
  });

  testWidgets('ReportPage chưa có quyền thì hiện nút cấp quyền', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ReportPage(platform: _Platform(null), loadApps: () async => []),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Chưa có số liệu'), findsOneWidget);
    expect(find.text('Cấp quyền'), findsOneWidget);
  });
}
