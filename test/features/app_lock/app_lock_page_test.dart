import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:safe_family_app/core/theme/app_theme.dart';
import 'package:safe_family_app/features/app_lock/data/app_lock_platform.dart';
import 'package:safe_family_app/features/app_lock/data/app_lock_store.dart';
import 'package:safe_family_app/features/app_lock/presentation/app_lock_controller.dart';
import 'package:safe_family_app/features/app_lock/presentation/app_lock_page.dart';
import 'package:safe_family_app/features/app_lock/presentation/app_lock_setup_page.dart';
import 'package:safe_family_app/features/home/presentation/home_page.dart';

import '../../helpers/app_lock_fakes.dart';

void main() {
  late FakeAppLockPlatform platform;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    platform = FakeAppLockPlatform();
  });

  // Không có ParentGuardScope → ParentGate cho qua (test màn lẻ).
  Future<AppLockController> pump(WidgetTester tester, Widget page) async {
    final controller = AppLockController(
      platform: platform,
      store: AppLockStore(prefs: SharedPreferencesAsync()),
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    await tester.pumpWidget(
      AppLockScope(
        controller: controller,
        child: MaterialApp(theme: AppTheme.light, home: page),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('danh sách: ẩn app hệ thống + app được bảo vệ, tìm kiếm', (
    tester,
  ) async {
    await pump(tester, const AppLockPage());
    expect(find.text('YouTube'), findsOneWidget);
    expect(find.text('Zalo'), findsOneWidget);
    expect(find.text('Chrome'), findsNothing, reason: 'app hệ thống');
    expect(find.text('Điện thoại'), findsNothing, reason: 'không được chặn');

    await tester.tap(find.text('Hiện cả app có sẵn của máy'));
    await tester.pumpAndSettle();
    expect(find.text('Chrome'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'za');
    await tester.pumpAndSettle();
    expect(find.text('Zalo'), findsOneWidget);
    expect(find.text('Chrome'), findsNothing);
  });

  testWidgets('chặn nhanh YouTube rồi mở tạm', (tester) async {
    final controller = await pump(tester, const AppLockPage());
    await tester.tap(find.text('Chặn nhanh YouTube'));
    await tester.pumpAndSettle();
    expect(platform.blocked, {'com.google.android.youtube'});
    expect(find.text('Chặn nhanh YouTube'), findsNothing);
    expect(find.text('Đang chặn'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.timer_outlined));
    await tester.pumpAndSettle();
    expect(platform.blocked, isEmpty);
    expect(platform.relocks.keys, ['com.google.android.youtube']);
    expect(find.textContaining('Đang mở tạm tới'), findsOneWidget);
    controller.dispose(); // hủy Timer tự chặn lại trước khi test kết thúc
  });

  testWidgets('công tắc Chặn', (tester) async {
    await pump(tester, const AppLockPage());
    final zalo = find.ancestor(
      of: find.text('Zalo'),
      matching: find.byType(ListTile),
    );
    await tester.tap(find.descendant(of: zalo, matching: find.byType(Switch)));
    await tester.pumpAndSettle();
    expect(platform.blocked, {'com.zing.zalo'});
  });

  testWidgets('thiếu quyền: báo đỏ, công tắc bị khóa', (tester) async {
    platform.perms = const AppLockPermissions(
      accessibility: false,
      exactAlarm: false,
      batteryUnrestricted: false,
    );
    await pump(tester, const AppLockPage());
    expect(find.text('Chưa bật đủ quyền khóa ứng dụng'), findsOneWidget);
    final switches = tester.widgetList<Switch>(find.byType(Switch));
    expect(switches.every((s) => s.onChanged == null), isTrue);
  });

  testWidgets('thiết lập: trạng thái từng quyền, mở đúng trang Cài đặt', (
    tester,
  ) async {
    platform.perms = const AppLockPermissions(
      accessibility: false,
      exactAlarm: true,
      batteryUnrestricted: false,
    );
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pump(tester, const AppLockSetupPage());
    expect(find.text('Chưa bật'), findsNWidgets(2));
    expect(find.text('Đã bật'), findsOneWidget);
    await tester.tap(find.text('Mở Cài đặt').first);
    expect(platform.opened, [AppLockSetting.accessibility]);
  });

  testWidgets('Trang chủ: cảnh báo đỏ khi đang chặn mà tắt Trợ năng', (
    tester,
  ) async {
    platform.blocked.add('com.google.android.youtube');
    platform.perms = const AppLockPermissions(
      accessibility: false,
      exactAlarm: true,
      batteryUnrestricted: true,
    );
    await pump(tester, const HomePage());
    expect(find.text('Khóa ứng dụng đang bị vô hiệu hóa'), findsOneWidget);
    expect(find.textContaining('Đang chặn 1 ứng dụng'), findsOneWidget);
  });

  testWidgets('Trang chủ: đủ quyền thì không cảnh báo', (tester) async {
    platform.blocked.add('com.google.android.youtube');
    await pump(tester, const HomePage());
    expect(find.text('Khóa ứng dụng đang bị vô hiệu hóa'), findsNothing);
  });
}
