import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:safe_family_app/core/theme/app_theme.dart';
import 'package:safe_family_app/features/profile/data/local_profile_repository.dart';
import 'package:safe_family_app/features/profile/presentation/profile_page.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('sửa tên phụ huynh và hiện chữ cái đầu', (tester) async {
    // Màn hình điện thoại 360 × 800 dp.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ProfilePage(repository: LocalProfileRepository()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Danh bạ gia đình'), findsNothing);
    await tester.tap(find.byTooltip('Sửa tên'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Nguyễn Thị Hoa');
    await tester.tap(find.widgetWithText(FilledButton, 'Lưu'));
    await tester.pumpAndSettle();

    expect(find.text('Nguyễn Thị Hoa'), findsOneWidget);
    expect(find.text('H'), findsOneWidget);
  });
}
