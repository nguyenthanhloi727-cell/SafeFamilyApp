import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safe_family_app/core/theme/app_theme.dart';
import 'package:safe_family_app/features/app_lock/presentation/block_schedules.dart';
import 'package:safe_family_app/features/time_limit/data/time_limit_platform.dart';
import 'package:safe_family_app/features/time_limit/domain/time_limit_config.dart';

class _Platform implements TimeLimitPlatform {
  _Platform(this.config, {this.pause = 0});

  final TimeLimitConfig config;
  final int pause;

  @override
  Future<TimeLimitConfig> load() async => config;

  @override
  Future<StudyStatus> studyStatus() async => const StudyStatus();

  @override
  Future<int> pauseMinutesLeft() async => pause;

  @override
  Future<bool> hasUsageAccess() async => true;

  @override
  Future<UsageToday?> usageToday() async =>
      const UsageToday(totalMinutes: 100, apps: {'com.yt': 60});

  @override
  Future<Map<String, String>> appLabels(List<String> packages) async => {
    for (final p in packages) p: 'YouTube',
  };

  @override
  dynamic noSuchMethod(Invocation invocation) async {}
}

// Thứ Hai 22:30.
DateTime _monday2230() => DateTime(2026, 1, 5, 22, 30);

Widget _host(_Platform platform) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(
    body: SingleChildScrollView(
      child: BlockSchedules(platform: platform, clock: _monday2230),
    ),
  ),
);

void main() {
  test('summarizeWeek gom ngày liền nhau cùng khung giờ', () {
    const night = BedtimeWindow(21 * 60, 6 * 60);
    const late = BedtimeWindow(22 * 60, 7 * 60);
    final week = <BedtimeWindow?>[
      night,
      night,
      night,
      night,
      night,
      late,
      late,
    ];
    expect(summarizeWeek(week), 'T2–T6 21:00–06:00 · T7, CN 22:00–07:00');
    expect(summarizeWeek(noBedtimeWeek()), '');
  });

  testWidgets('hiện giờ ngủ đang chặn và hạn mức app hết giờ', (tester) async {
    final week = noBedtimeWeek();
    week[0] = const BedtimeWindow(21 * 60, 6 * 60);
    final limits = unlimitedWeek()..[0] = 60;
    final platform = _Platform(
      TimeLimitConfig(
        enabled: true,
        apps: {'com.yt': limits},
        bedtimeEnabled: true,
        bedtime: week,
      ),
    );
    await tester.pumpWidget(_host(platform));
    await tester.pumpAndSettle();

    expect(find.text('Chặn theo giờ'), findsOneWidget);
    expect(find.text('T2 21:00–06:00'), findsOneWidget);
    expect(find.text('Đang chặn lúc này'), findsOneWidget);
    expect(find.textContaining('YouTube'), findsOneWidget);
    expect(find.textContaining('hết giờ, đang chặn'), findsOneWidget);
    expect(find.text('Giờ học'), findsOneWidget);
    expect(find.text('Chưa đặt'), findsOneWidget);
  });

  testWidgets('đang tạm dừng máy thì hiện thẻ Tạm dừng máy', (tester) async {
    await tester.pumpWidget(_host(_Platform(TimeLimitConfig(), pause: 30)));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Khóa mọi ứng dụng, còn 30 phút'),
      findsOneWidget,
    );
  });

  testWidgets('không tạm dừng thì không có thẻ Tạm dừng máy', (tester) async {
    await tester.pumpWidget(_host(_Platform(TimeLimitConfig())));
    await tester.pumpAndSettle();
    expect(find.text('Tạm dừng máy'), findsNothing);
  });
}
