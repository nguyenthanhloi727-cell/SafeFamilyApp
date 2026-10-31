import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:safe_family_app/app/app.dart';
import 'package:safe_family_app/core/network/connection_session.dart';
import 'package:safe_family_app/core/permissions/permission_registry.dart';
import 'package:safe_family_app/core/security/parent_guard.dart';
import 'package:safe_family_app/core/settings/setup_settings.dart';
import 'package:safe_family_app/features/parental/presentation/first_run_setup_page.dart';
import 'package:safe_family_app/features/alarm/presentation/alarm_page.dart';
import 'package:safe_family_app/features/home/presentation/home_page.dart';
import 'package:safe_family_app/features/profile/presentation/profile_page.dart';
import 'package:safe_family_app/features/team/presentation/team_page.dart';

import 'helpers/security_fakes.dart';

const _tabs = <(String, Type)>[
  ('Trang chủ', HomePage),
  ('Báo thức', AlarmPage),
  ('Nhóm', TeamPage),
  ('Cá nhân', ProfilePage),
];

Future<void> _tapTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(
      of: find.byType(BottomNavigationBar),
      matching: find.text(label),
    ),
  );
  // Không dùng pumpAndSettle: IndexedStack dựng cả 4 tab ngay từ đầu, tab Nhóm
  // đọc assets thật (IO thật) nên vòng loading chưa dừng trong thời gian giả
  // của test. Chỉ cần xong hiệu ứng chuyển tab.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

/// Máy giả chưa cấp quyền nào (kênh thật không trả lời trong test).
class _NoPermissions implements PermissionPlatform {
  @override
  Future<Map<String, bool>> status() async => {};
  @override
  Future<bool> openSettings(AppPermission permission) async => true;
  @override
  Future<bool> removeDeviceAdmin() async => true;
}

/// Máy đã chọn "Dùng một máy" (bỏ qua màn chọn vai trò).
Future<ConnectionSession> localConnection() async {
  final connection = ConnectionSession(store: InMemorySecureStore());
  await connection.setMode(ConnectionMode.local);
  await connection.load();
  return connection;
}

void main() {
  setUp(() {
    // Tab Cá nhân đọc dữ liệu đã lưu — dùng bộ nhớ giả, không đụng máy thật.
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  /// App đã thiết lập PIN (bỏ qua màn thiết lập lần đầu).
  Future<void> pumpApp(WidgetTester tester, {bool childMode = false}) async {
    final guard = await configuredGuard(childMode: childMode);
    final setup = SetupSettings();
    await setup.load();
    await setup.markDone(); // Bỏ qua wizard cấp quyền.
    final connection = await localConnection();
    await tester.pumpWidget(
      SafeFamilyApp(guard: guard, setup: setup, connection: connection),
    );
    await tester.pump();
  }

  Future<void> enterPin(WidgetTester tester, String pin) async {
    for (final digit in pin.split('')) {
      await tester.tap(find.bySemanticsLabel('Số $digit'));
      await tester.pump();
    }
    await tester.tap(find.byTooltip('Xác nhận'));
    await tester.pumpAndSettle();
  }

  testWidgets('lần đầu mở app: đặt PIN 2 lần → bật vân tay → vào app', (
    tester,
  ) async {
    final guard = ParentGuard(
      store: InMemorySecureStore(),
      biometrics: FakeBiometrics(),
      hasher: fastHasher,
    );
    await guard.load();
    tester.view.physicalSize = const Size(1080, 3600); // 360 × 1200 dp
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final permissions = PermissionRegistry(platform: _NoPermissions());
    await permissions.refresh();
    await tester.pumpWidget(
      SafeFamilyApp(
        guard: guard,
        permissions: permissions,
        connection: await localConnection(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Chào mừng đến SafeFamily'), findsOneWidget);
    expect(find.text(biometricOwnershipWarning), findsOneWidget);
    await tester.ensureVisible(find.text('Bắt đầu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bắt đầu'));
    await tester.pumpAndSettle();

    await enterPin(tester, '1234');
    expect(find.text('Mã PIN không được là dãy số liên tiếp'), findsOneWidget);

    await enterPin(tester, testPin);
    expect(find.text('Nhập lại mã PIN'), findsOneWidget);
    await enterPin(tester, testPin);

    // Mã khôi phục hiện một lần; phải tích "đã ghi lại" mới đi tiếp được.
    expect(find.text('Mã khôi phục PIN'), findsOneWidget);
    expect(guard.isConfigured, isFalse);
    await tester.tap(find.byKey(const Key('recovery-written')));
    await tester.pump();
    await tester.tap(find.text('Tiếp tục'));
    await tester.pumpAndSettle();

    expect(find.text('Bật mở khóa bằng vân tay?'), findsOneWidget);
    await tester.tap(find.text('Bật'));
    await tester.pumpAndSettle();

    // Bước cuối: quản trị thiết bị (có thể để sau).
    expect(find.text('Chống gỡ SafeFamily'), findsOneWidget);
    await tester.tap(find.text('Để sau'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(guard.isConfigured, isTrue);
    expect(guard.hasRecoveryCode, isTrue);
    expect(guard.biometricEnabled, isTrue);
    // Chưa có cờ setup_done → vào wizard cấp quyền trước khi tới app chính.
    await tester.pump();
    expect(find.text('Thiết lập quyền'), findsOneWidget);
    expect(find.byType(BottomNavigationBar), findsNothing);
  });

  testWidgets('chế độ trẻ em: có dải báo ở đầu màn hình', (tester) async {
    await pumpApp(tester, childMode: true);
    expect(find.text('Đang ở chế độ trẻ em'), findsOneWidget);
  });

  testWidgets('BottomNavigationBar chuyển đủ 4 tab', (tester) async {
    await pumpApp(tester);

    final barFinder = find.byType(BottomNavigationBar);
    expect(barFinder, findsOneWidget);
    final bar = tester.widget<BottomNavigationBar>(barFinder);
    expect(bar.type, BottomNavigationBarType.fixed);
    expect(bar.items.map((item) => item.label), _tabs.map((tab) => tab.$1));

    // Đi 1 → 5 rồi quay lại tab đầu.
    for (final (index, (label, page)) in [..._tabs, _tabs.first].indexed) {
      await _tapTab(tester, label);
      final expected = index % _tabs.length;
      expect(
        tester.widget<BottomNavigationBar>(barFinder).currentIndex,
        expected,
        reason: 'Bấm "$label" phải chọn tab $expected',
      );
      expect(find.byType(page), findsOneWidget, reason: '"$label" phải hiện');
      for (final (_, other) in _tabs.where((tab) => tab.$2 != page)) {
        expect(find.byType(other), findsNothing, reason: 'Chỉ hiện 1 tab');
      }
    }
  });

  testWidgets('Giữ trạng thái tab khi chuyển qua lại (IndexedStack)', (
    tester,
  ) async {
    await pumpApp(tester);

    await _tapTab(tester, 'Báo thức');
    final typed = find.byKey(const Key('typed-command'));
    await tester.enterText(typed, 'Đặt báo thức 6 giờ');
    await tester.pump();

    await _tapTab(tester, 'Nhóm');
    await _tapTab(tester, 'Báo thức');
    expect(
      tester.widget<TextField>(typed).controller!.text,
      'Đặt báo thức 6 giờ',
      reason: 'Quay lại tab Báo thức phải giữ câu đã gõ',
    );
  });
}
