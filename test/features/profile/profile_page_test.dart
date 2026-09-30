import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:safe_family_app/core/theme/app_theme.dart';
import 'package:safe_family_app/features/profile/data/local_profile_repository.dart';
import 'package:safe_family_app/features/profile/presentation/profile_page.dart';

import '../../helpers/fake_launcher.dart';

void main() {
  late FakeLauncher launcher;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    launcher = FakeLauncher();
  });

  Future<void> pumpPage(WidgetTester tester, {FakeLauncher? using}) async {
    // Màn hình điện thoại 360 × 800 dp.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ProfilePage(
          repository: LocalProfileRepository(),
          launcher: using ?? launcher,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openAddDialog(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(TextButton, 'Thêm'));
    await tester.pumpAndSettle();
  }

  testWidgets('lần đầu có sẵn Mẹ, Bố chưa có số', (tester) async {
    await pumpPage(tester);

    expect(find.text('Mẹ'), findsOneWidget);
    expect(find.text('Bố'), findsOneWidget);
    expect(find.text('Chạm để thêm số'), findsNWidgets(2));
  });

  testWidgets('thêm 1 liên hệ và thấy nó trong danh sách', (tester) async {
    await pumpPage(tester);

    await openAddDialog(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Ông'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('phone-field')),
      '090 123.4567',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Lưu'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Ông'), findsOneWidget);
    expect(find.text('0901234567'), findsOneWidget, reason: 'số đã chuẩn hoá');
  });

  testWidgets('chọn "Khác" thì tự gõ tên gọi', (tester) async {
    await pumpPage(tester);

    await openAddDialog(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Khác'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('custom-label-field')),
      'Cô Lan',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Lưu'));
    await tester.pumpAndSettle();

    expect(find.text('Cô Lan'), findsOneWidget);
  });

  testWidgets('số sai báo lỗi ngay dưới ô nhập và không lưu', (tester) async {
    await pumpPage(tester);

    await openAddDialog(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Bà'));
    await tester.enterText(find.byKey(const Key('phone-field')), '12345');
    await tester.pump();

    expect(find.text('Số điện thoại phải dài 9–12 chữ số'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Lưu'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget, reason: 'vẫn mở');
  });

  testWidgets('chưa chọn tên gọi thì báo lỗi', (tester) async {
    await pumpPage(tester);

    await openAddDialog(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Lưu'));
    await tester.pump();

    expect(find.text('Chọn tên gọi'), findsOneWidget);
  });

  testWidgets('chạm thẻ chưa có số thì mở hộp thoại nhập số', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.text('Mẹ'));
    await tester.pumpAndSettle();
    expect(find.text('Nhập số cho Mẹ'), findsOneWidget);
    expect(launcher.dialed, isEmpty, reason: 'không gọi khi chưa có số');

    await tester.enterText(find.byKey(const Key('phone-field')), '0901234567');
    await tester.tap(find.widgetWithText(FilledButton, 'Lưu'));
    await tester.pumpAndSettle();

    // Có số rồi: chạm lần nữa thì mở màn quay số với số đó.
    await tester.tap(find.text('Mẹ'));
    await tester.pumpAndSettle();
    expect(launcher.dialed, ['0901234567']);
  });

  testWidgets('xóa phải xác nhận', (tester) async {
    await pumpPage(tester);

    Future<void> openDelete() async {
      await tester.tap(find.byTooltip('Tùy chọn Bố'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xóa'));
      await tester.pumpAndSettle();
    }

    await openDelete();
    expect(find.text('Xóa liên hệ Bố?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Hủy'));
    await tester.pumpAndSettle();
    expect(find.text('Bố'), findsOneWidget, reason: 'Hủy thì không xóa');

    await openDelete();
    await tester.tap(find.widgetWithText(FilledButton, 'Xóa'));
    await tester.pumpAndSettle();
    expect(find.text('Bố'), findsNothing);
  });

  testWidgets('sửa tên phụ huynh và hiện chữ cái đầu', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.byTooltip('Sửa tên'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Nguyễn Thị Hoa');
    await tester.tap(find.widgetWithText(FilledButton, 'Lưu'));
    await tester.pumpAndSettle();

    expect(find.text('Nguyễn Thị Hoa'), findsOneWidget);
    expect(find.text('H'), findsOneWidget);
  });

  testWidgets('bấm Mở YouTube', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.text('Mở YouTube'));
    await tester.pumpAndSettle();

    expect(launcher.youTubeOpened, 1);
  });

  testWidgets('mở app ngoài thất bại thì báo SnackBar, không crash', (
    tester,
  ) async {
    await pumpPage(tester, using: FakeLauncher(succeed: false));

    await tester.tap(find.text('Mở YouTube'));
    await tester.pump();

    expect(find.text('Không mở được YouTube.'), findsOneWidget);
  });
}
