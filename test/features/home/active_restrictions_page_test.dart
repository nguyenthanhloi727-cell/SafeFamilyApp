import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safe_family_app/app/feature_registry.dart';
import 'package:safe_family_app/core/permissions/permission_registry.dart';
import 'package:safe_family_app/core/security/device_guard.dart';
import 'package:safe_family_app/core/theme/app_theme.dart';
import 'package:safe_family_app/features/home/presentation/active_restrictions_page.dart';
import 'package:safe_family_app/features/time_limit/data/time_limit_platform.dart';
import 'package:safe_family_app/features/time_limit/domain/time_limit_config.dart';

class _Platform implements TimeLimitPlatform {
  int pause = 0;

  @override
  Future<TimeLimitConfig> load() async => TimeLimitConfig();
  @override
  Future<StudyStatus> studyStatus() async => const StudyStatus();
  @override
  Future<int> pauseMinutesLeft() async => pause;
  @override
  Future<void> stopPause() async => pause = 0;
  @override
  Future<DateTime?> totalLimitDisabledUntil() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) async {}
}

class _Permissions implements PermissionPlatform {
  @override
  Future<Map<String, bool>> status() async => {};
  @override
  Future<bool> openSettings(AppPermission permission) async => true;
  @override
  Future<bool> removeDeviceAdmin() async => true;
}

void main() {
  test('formatCountdown giờ:phút:giây', () {
    expect(formatCountdown(const Duration(hours: 1, minutes: 5, seconds: 9)),
        '01:05:09');
    expect(remainingUntil(DateTime(2026), DateTime(2027)), Duration.zero);
  });

  testWidgets('đếm ngược từng giây, bấm Tắt thì dòng biến mất', (tester) async {
    final platform = _Platform()..pause = 30;
    var now = DateTime(2026, 10, 28, 22);
    final permissions = PermissionRegistry(platform: _Permissions());
    await permissions.refresh();
    await tester.pumpWidget(
      PermissionRegistryScope(
        registry: permissions,
        child: MaterialApp(
          theme: AppTheme.light,
          home: ActiveRestrictionsPage(
            clock: () => now,
            registry: FeatureRegistry(
              timeLimit: platform,
              deviceGuard: const NoDeviceGuard(),
              clock: () => now,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Còn 00:30:00'), findsOne);

    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Còn 00:29:59'), findsOne);

    await tester.tap(find.byKey(const Key('restriction-off-pause')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('restriction-feature-pause')), findsNothing);
    expect(find.byKey(const Key('restrictions-empty')), findsOne);
  });
}
