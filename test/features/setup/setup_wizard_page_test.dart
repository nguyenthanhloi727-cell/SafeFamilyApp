import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safe_family_app/core/network/connection_session.dart';
import 'package:safe_family_app/core/permissions/permission_registry.dart';
import 'package:safe_family_app/core/settings/setup_settings.dart';
import 'package:safe_family_app/core/theme/app_theme.dart';
import 'package:safe_family_app/features/setup/setup_wizard_page.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _Platform implements PermissionPlatform {
  Map<String, bool> granted = {};
  final opened = <AppPermission>[];

  @override
  Future<Map<String, bool>> status() async => Map.of(granted);

  @override
  Future<bool> openSettings(AppPermission permission) async {
    opened.add(permission);
    return true;
  }

  @override
  Future<bool> removeDeviceAdmin() async => true;
}

void main() {
  wizardStepsByRole();
  late _Platform platform;
  late PermissionRegistry registry;
  var finished = 0;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    platform = _Platform();
    registry = PermissionRegistry(platform: platform);
    finished = 0;
  });

  Future<void> pump(WidgetTester tester) async {
    await registry.refresh();
    await tester.pumpWidget(
      PermissionRegistryScope(
        registry: registry,
        child: MaterialApp(
          theme: AppTheme.light,
          home: SetupWizardPage(onFinished: () => finished++),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('bước đầu là hướng dẫn cài đặt bị hạn chế, Để sau đi hết', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Cho phép cài đặt bị hạn chế'), findsOneWidget);
    expect(find.text('Bước 1/8'), findsOneWidget);

    for (var i = 0; i < 9; i++) {
      await tester.ensureVisible(find.byKey(const Key('wizard-skip')));
      await tester.tap(find.byKey(const Key('wizard-skip')));
      await tester.pump();
    }
    expect(finished, 1);
  });

  testWidgets('bắt buộc: không có nút "Để sau" ở mọi bước', (tester) async {
    await registry.refresh();
    await tester.pumpWidget(
      PermissionRegistryScope(
        registry: registry,
        child: MaterialApp(
          theme: AppTheme.light,
          home: SetupWizardPage(enforced: true, onFinished: () => finished++),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('wizard-skip')), findsNothing);

    await tester.tap(find.byKey(const Key('wizard-continue')));
    await tester.pump();
    expect(find.text(AppPermission.accessibility.label), findsOneWidget);
    expect(find.byKey(const Key('wizard-skip')), findsNothing);
    expect(finished, 0);
  });

  testWidgets(
    'bật liền nhiều quyền trong một lần thì nhảy qua hết bước đã cấp',
    (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('wizard-continue')));
      await tester.pump();
      expect(find.text(AppPermission.accessibility.label), findsOneWidget);

      // Bật cả hai Trợ năng cùng lúc rồi quay lại app.
      platform.granted = {'accessibility': true, 'settings_guard': true};
      await registry.refresh();
      await tester.pump();
      expect(find.text(AppPermission.usageAccess.label), findsOneWidget);
      expect(find.text('Bước 4/8'), findsOneWidget);
    },
  );

  testWidgets('bật quyền ở Cài đặt rồi quay lại thì tự sang bước kế', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('wizard-continue')));
    await tester.pump();
    expect(find.text(AppPermission.accessibility.label), findsOneWidget);

    await tester.tap(find.byKey(const Key('wizard-open')));
    await tester.pump();
    expect(platform.opened, [AppPermission.accessibility]);

    platform.granted['accessibility'] = true;
    await registry.refresh();
    await tester.pump();
    expect(find.text(AppPermission.settingsGuard.label), findsOneWidget);
    expect(find.text('Bước 3/8'), findsOneWidget);
  });

  testWidgets('đủ quyền rồi thì không hiện bước nào, kết thúc ngay', (
    tester,
  ) async {
    platform.granted = {for (final p in AppPermission.values) p.id: true};
    await pump(tester);
    await tester.pump();
    expect(finished, 1);
  });

  test('SetupSettings lưu cờ setup_done', () async {
    final first = SetupSettings();
    await first.load();
    expect(first.isDone, isFalse);
    await first.markDone();
    final second = SetupSettings();
    await second.load();
    expect(second.isDone, isTrue);
  });
}

void wizardStepsByRole() {
  group('wizardSteps theo vai trò', () {
    test('máy mẹ chỉ có bước Thông báo, không có bước hướng dẫn', () async {
      final platform = _Platform();
      final registry = PermissionRegistry(platform: platform);
      await registry.refresh();
      expect(wizardSteps(registry, mode: ConnectionMode.parent), [
        AppPermission.notifications,
      ]);
    });

    test('máy mẹ đã cấp Thông báo thì không còn bước nào', () async {
      final platform = _Platform()..granted = {'notifications': true};
      final registry = PermissionRegistry(platform: platform);
      await registry.refresh();
      expect(wizardSteps(registry, mode: ConnectionMode.parent), isEmpty);
    });

    test('máy con có hướng dẫn rồi đủ mọi quyền', () async {
      final registry = PermissionRegistry(platform: _Platform());
      await registry.refresh();
      final steps = wizardSteps(registry, mode: ConnectionMode.child);
      expect(steps.first, isNull);
      expect(steps.skip(1), AppPermission.values);
    });
  });
}
