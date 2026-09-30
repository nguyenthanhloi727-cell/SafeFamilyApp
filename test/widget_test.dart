import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:safe_family_app_nguyenthanhloi/app/app.dart';
import 'package:safe_family_app_nguyenthanhloi/core/security/parent_guard.dart';
import 'package:safe_family_app_nguyenthanhloi/features/parental/presentation/first_run_setup_page.dart';
import 'package:safe_family_app_nguyenthanhloi/features/alarm/presentation/alarm_page.dart';
import 'package:safe_family_app_nguyenthanhloi/features/home/presentation/home_page.dart';
import 'package:safe_family_app_nguyenthanhloi/features/profile/presentation/profile_page.dart';
import 'package:safe_family_app_nguyenthanhloi/features/team/presentation/team_page.dart';

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

void main() {
  setUp(() {
    // Tab Cá nhân đọc dữ liệu đã lưu — dùng bộ nhớ giả, không đụng máy thật.
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  /// App đã thiết lập PIN (bỏ qua màn thiết lập lần đầu).
  Future<void> pumpApp(WidgetTester tester, {bool childMode = false}) async {
    final guard = await configuredGuard(childMode: childMode);
    await tester.pumpWidget(SafeFamilyApp(guard: guard));
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
    tester.view.physicalSize = const Size(1080, 2400); // 360 × 800 dp
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(SafeFamilyApp(guard: guard));
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

    expect(find.text('Bật mở khóa bằng vân tay?'), findsOneWidget);
    await tester.tap(find.text('Bật'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(guard.isConfigured, isTrue);
    expect(guard.biometricEnabled, isTrue);
    expect(find.byType(BottomNavigationBar), findsOneWidget);
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
