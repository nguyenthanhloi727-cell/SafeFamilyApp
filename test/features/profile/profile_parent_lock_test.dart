import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:safe_family_app/core/security/parent_guard.dart';
import 'package:safe_family_app/core/theme/app_theme.dart';
import 'package:safe_family_app/features/profile/data/local_profile_repository.dart';
import 'package:safe_family_app/features/profile/presentation/profile_page.dart';

import '../../helpers/security_fakes.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
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
          home: ProfilePage(repository: LocalProfileRepository()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('không còn công tắc chế độ trẻ em, có mục Bảo vệ máy', (
    tester,
  ) async {
    final guard = await configuredGuard();
    await pumpProfile(tester, guard);

    expect(find.text('Chế độ trẻ em'), findsNothing);
    final tile = find.widgetWithText(ListTile, 'Bảo vệ máy');
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    expect(tile, findsOneWidget);
  });
}
