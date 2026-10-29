import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
    expect(find.text('Bước 1/9'), findsOneWidget);

    for (var i = 0; i < 9; i++) {
      await tester.ensureVisible(find.byKey(const Key('wizard-skip')));
      await tester.tap(find.byKey(const Key('wizard-skip')));
      await tester.pump();
    }
    expect(finished, 1);
  });

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
    expect(find.text('Bước 3/9'), findsOneWidget);
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
