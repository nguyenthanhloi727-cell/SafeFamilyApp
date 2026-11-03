import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safe_family_app/core/theme/app_theme.dart';
import 'package:safe_family_app/features/app_lock/data/app_lock_store.dart';
import 'package:safe_family_app/features/app_lock/presentation/app_lock_controller.dart';
import 'package:safe_family_app/features/connection/presentation/child_home_page.dart';
import 'package:safe_family_app/features/time_limit/data/time_limit_platform.dart';
import 'package:safe_family_app/features/time_limit/domain/time_limit_config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../../helpers/app_lock_fakes.dart';

class _Platform implements TimeLimitPlatform {
  _Platform({this.pause = 0, this.limit, this.used = 0});

  final int pause;
  final int? limit;
  final int used;

  @override
  Future<TimeLimitConfig> load() async => TimeLimitConfig(
    enabled: limit != null,
    total: List<int?>.filled(7, limit),
  );
  @override
  Future<UsageToday?> usageToday() async => UsageToday(totalMinutes: used);
  @override
  Future<int> bonusMinutes() async => 0;
  @override
  Future<int> pauseMinutesLeft() async => pause;
  @override
  Future<StudyStatus> studyStatus() async => const StudyStatus();
  @override
  Future<Map<String, String>> appLabels(List<String> packages) async => {
    for (final p in packages)
      p: p == 'com.google.android.youtube' ? 'YouTube' : p,
  };

  @override
  dynamic noSuchMethod(Invocation invocation) async {}
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  Future<void> pump(
    WidgetTester tester,
    TimeLimitPlatform platform, {
    Set<String> blocked = const {},
  }) async {
    final controller = AppLockController(
      platform: FakeAppLockPlatform(blocked: {...blocked}),
      store: AppLockStore(prefs: SharedPreferencesAsync()),
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    await tester.pumpWidget(
      AppLockScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light,
          home: ChildHomePage(
            platform: platform,
            refreshEvery: const Duration(days: 1),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('hiện app đang bị chặn và thời gian còn lại hôm nay', (t) async {
    await pump(
      t,
      _Platform(limit: 120, used: 45),
      blocked: {'com.google.android.youtube'},
    );
    expect(find.text('YouTube'), findsOneWidget);
    expect(find.text('Đang bị chặn'), findsOneWidget);
    expect(find.text('Hôm nay còn 1 giờ 15 phút'), findsOneWidget);
    expect(find.text('Đã dùng 45 phút / 2 giờ.'), findsOneWidget);
    expect(find.byKey(const Key('child-parent-area')), findsOneWidget);
  });

  testWidgets('chưa chặn gì: báo rõ; máy tạm dừng: hiện thẻ tạm dừng', (
    t,
  ) async {
    await pump(t, _Platform(pause: 20));
    expect(find.text('Hiện chưa có ứng dụng nào bị chặn.'), findsOneWidget);
    expect(find.text('Máy đang tạm dừng'), findsOneWidget);
    expect(find.text('Còn 20 phút.'), findsOneWidget);
  });
}
