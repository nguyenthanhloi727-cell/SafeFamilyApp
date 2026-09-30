import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:safe_family_app/core/security/parent_guard.dart';
import 'package:safe_family_app/core/security/unlock_log.dart';
import 'package:safe_family_app/core/theme/app_theme.dart';
import 'package:safe_family_app/features/profile/data/local_profile_repository.dart';
import 'package:safe_family_app/features/profile/presentation/profile_page.dart';

import '../../helpers/fake_launcher.dart';
import '../../helpers/security_fakes.dart';

void main() {
  late FakeLauncher launcher;

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    launcher = FakeLauncher();
    // Có sẵn 1 liên hệ có số để thử nút gọi.
    await LocalProfileRepository().addContact(
      label: 'Ông',
      phone: '0901234567',
    );
  });

  Future<void> pumpProfile(WidgetTester tester, ParentGuard guard) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ParentGuardScope(
        guard: guard,
        child: MaterialApp(
          theme: AppTheme.light,
          home: ProfilePage(
            repository: LocalProfileRepository(),
            launcher: launcher,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> enterPin(WidgetTester tester, String pin) async {
    for (final digit in pin.split('')) {
      await tester.tap(find.bySemanticsLabel('Số $digit'));
      await tester.pump();
    }
    await tester.tap(find.byTooltip('Xác nhận'));
    await tester.pumpAndSettle();
  }

  testWidgets('chế độ trẻ em: sửa danh bạ bắt xác thực PIN', (tester) async {
    final guard = await configuredGuard(childMode: true);
    await pumpProfile(tester, guard);

    await tester.tap(find.widgetWithText(TextButton, 'Thêm'));
    await tester.pumpAndSettle();
    expect(find.text('Nhập mã PIN phụ huynh'), findsOneWidget);
    expect(find.text('để: Thêm liên hệ'), findsOneWidget);

    // Hủy → không mở hộp thoại thêm liên hệ.
    await tester.tap(find.byTooltip('Hủy'));
    await tester.pumpAndSettle();
    expect(find.text('Thêm liên hệ'), findsNothing);

    // PIN sai → báo còn 4 lần; PIN đúng → mở hộp thoại.
    await tester.tap(find.widgetWithText(TextButton, 'Thêm'));
    await tester.pumpAndSettle();
    await enterPin(tester, '1357');
    expect(find.textContaining('Còn 4 lần thử'), findsOneWidget);
    await enterPin(tester, testPin);
    expect(find.text('Thêm liên hệ'), findsOneWidget);

    final log = await guard.log.entries();
    expect(log.first.result, UnlockResult.success);
    expect(log[1].result, UnlockResult.failure);
  });

  testWidgets('chế độ trẻ em: bấm gọi người nhà KHÔNG bị khóa', (tester) async {
    final guard = await configuredGuard(childMode: true);
    await pumpProfile(tester, guard);

    await tester.tap(find.text('Ông'));
    await tester.pumpAndSettle();

    expect(find.text('Nhập mã PIN phụ huynh'), findsNothing);
    expect(launcher.dialed, ['0901234567']);
  });

  testWidgets(
    'chế độ trẻ em + đã bật vân tay: mở khóa bằng vân tay, không hỏi PIN',
    (tester) async {
      final bio = FakeBiometrics();
      final guard = await configuredGuard(
        biometrics: bio,
        biometricEnabled: true,
        childMode: true,
      );
      await guard.refreshCapability();
      await pumpProfile(tester, guard);

      await tester.tap(find.byTooltip('Tùy chọn Ông'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sửa'));
      await tester.pumpAndSettle();

      expect(bio.calls, 1);
      expect(find.text('Nhập mã PIN phụ huynh'), findsNothing);
      expect(find.text('Sửa liên hệ'), findsOneWidget);
    },
  );

  testWidgets('ngoài chế độ trẻ em: sửa danh bạ không hỏi gì', (tester) async {
    final guard = await configuredGuard();
    await pumpProfile(tester, guard);

    await tester.tap(find.widgetWithText(TextButton, 'Thêm'));
    await tester.pumpAndSettle();

    expect(find.text('Nhập mã PIN phụ huynh'), findsNothing);
    expect(find.text('Thêm liên hệ'), findsOneWidget);
  });

  testWidgets('công tắc chế độ trẻ em: bật ngay, thoát phải nhập PIN', (
    tester,
  ) async {
    final guard = await configuredGuard();
    await pumpProfile(tester, guard);

    final toggle = find.widgetWithText(SwitchListTile, 'Chế độ trẻ em');
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(guard.childMode, isTrue);
    expect(find.text('Nhập mã PIN phụ huynh'), findsNothing);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('để: Thoát chế độ trẻ em'), findsOneWidget);
    await enterPin(tester, testPin);
    expect(guard.childMode, isFalse);
  });
}
