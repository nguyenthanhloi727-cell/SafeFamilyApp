import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safe_family_app/core/permissions/permission_registry.dart';
import 'package:safe_family_app/core/theme/app_theme.dart';
import 'package:safe_family_app/features/parental/presentation/app_permissions_page.dart';

class _Platform implements PermissionPlatform {
  Map<String, bool> granted = {};
  final opened = <AppPermission>[];
  bool adminRemoved = false;

  @override
  Future<Map<String, bool>> status() async => Map.of(granted);

  @override
  Future<bool> openSettings(AppPermission permission) async {
    opened.add(permission);
    return true;
  }

  @override
  Future<bool> removeDeviceAdmin() async {
    granted['device_admin'] = false;
    return adminRemoved = true;
  }
}

void main() {
  late _Platform platform;
  late PermissionRegistry registry;

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await registry.refresh();
    await tester.pumpWidget(
      PermissionRegistryScope(
        registry: registry,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const AppPermissionsPage(),
        ),
      ),
    );
  }

  setUp(() {
    platform = _Platform()
      ..granted = {'accessibility': true, 'device_admin': true};
    registry = PermissionRegistry(platform: platform);
  });

  tearDown(() => registry.dispose());

  testWidgets('quyền đã cấp có nút Tắt, chưa cấp có nút Bật', (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('permission-off-accessibility')), findsOne);
    expect(find.byKey(const Key('permission-on-usage_access')), findsOne);
    expect(find.byKey(const Key('permission-off-usage_access')), findsNothing);
  });

  testWidgets('Tắt mở đúng trang Cài đặt của quyền', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('permission-off-accessibility')));
    await tester.pump();
    expect(platform.opened, [AppPermission.accessibility]);
  });

  testWidgets('Tắt Quản trị thiết bị thì gỡ thẳng, không mở Cài đặt', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('permission-off-device_admin')));
    await tester.pumpAndSettle();
    expect(platform.adminRemoved, isTrue);
    expect(platform.opened, isEmpty);
    expect(find.byKey(const Key('permission-on-device_admin')), findsOne);
  });

  testWidgets('Bật mở trang Cài đặt', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('permission-on-battery')));
    await tester.pump();
    expect(platform.opened, [AppPermission.battery]);
  });
}
