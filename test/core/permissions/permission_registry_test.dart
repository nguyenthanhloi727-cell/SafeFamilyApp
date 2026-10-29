import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safe_family_app/core/permissions/permission_registry.dart';

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
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Platform platform;
  late PermissionRegistry registry;

  setUp(() {
    platform = _Platform();
    registry = PermissionRegistry(platform: platform);
  });

  tearDown(() => registry.dispose());

  test('liệt kê đủ mọi quyền, chưa cấp thì missing', () async {
    await registry.refresh();
    expect(registry.entries.length, AppPermission.values.length);
    expect(registry.granted, isEmpty);
    expect(registry.missing.length, AppPermission.values.length);
  });

  test(
    'quyền được cấp hiện trong granted, đổi trạng thái thì báo listener',
    () async {
      var notified = 0;
      registry.addListener(() => notified++);
      platform.granted = {'accessibility': true, 'battery': true};
      await registry.refresh();
      expect(registry.isGranted(AppPermission.accessibility), isTrue);
      expect(registry.isGranted(AppPermission.usageAccess), isFalse);
      expect(registry.granted.map((e) => e.id), ['accessibility', 'battery']);
      expect(notified, 1);

      await registry.refresh(); // không đổi → không báo
      expect(notified, 1);
    },
  );

  test(
    'app resumed thì đọc lại quyền (vừa bật/tắt trong Cài đặt máy)',
    () async {
      registry.start();
      await Future<void>.delayed(Duration.zero);
      expect(registry.isGranted(AppPermission.usageAccess), isFalse);

      platform.granted = {'usage_access': true};
      registry.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(registry.isGranted(AppPermission.usageAccess), isTrue);

      platform.granted = {};
      registry.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(registry.isGranted(AppPermission.usageAccess), isFalse);
    },
  );

  test('openSettings chuyển đúng quyền sang platform', () async {
    await registry.openSettings(AppPermission.notifications);
    expect(platform.opened, [AppPermission.notifications]);
  });

  test('removeDeviceAdmin tắt thẳng rồi cập nhật trạng thái', () async {
    platform.granted = {'device_admin': true};
    await registry.refresh();
    expect(registry.isGranted(AppPermission.deviceAdmin), isTrue);

    expect(await registry.removeDeviceAdmin(), isTrue);
    expect(registry.isGranted(AppPermission.deviceAdmin), isFalse);
  });

  test('id không trùng nhau', () {
    final ids = AppPermission.values.map((p) => p.id).toSet();
    expect(ids.length, AppPermission.values.length);
  });
}
