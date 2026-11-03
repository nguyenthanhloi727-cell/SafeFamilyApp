import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:safe_family_app/app/app_shell.dart';
import 'package:safe_family_app/core/network/api_client.dart';
import 'package:safe_family_app/core/network/api_scope.dart';
import 'package:safe_family_app/core/network/connection_session.dart';
import 'package:safe_family_app/core/security/parent_guard.dart';
import 'package:safe_family_app/core/theme/app_theme.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../../helpers/security_fakes.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  Future<Widget> app(ConnectionMode mode) async {
    final session = ConnectionSession(store: InMemorySecureStore());
    await session.load();
    await session.setBaseUrl('https://api.test');
    await session.setMode(mode);
    if (mode == ConnectionMode.parent) {
      await session.saveParentTokens(
        access: 'a',
        refresh: 'r',
        email: 'me@test.vn',
      );
    }
    final client = MockClient(
      (r) async => http.Response(
        jsonEncode(<Object?>[]),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    return ParentGuardScope(
      guard: await configuredGuard(),
      child: ConnectionScope(
        session: session,
        child: ApiScope(
          client: ApiClient(session: session, client: client),
          child: MaterialApp(theme: AppTheme.light, home: const AppShell()),
        ),
      ),
    );
  }

  Finder navLabel(String label) => find.descendant(
    of: find.byType(BottomNavigationBar),
    matching: find.text(label),
  );

  testWidgets('máy mẹ: đúng 2 tab Con + Tài khoản, tab Tài khoản có đủ mục', (
    t,
  ) async {
    t.view.physicalSize = const Size(1080, 3600);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(await app(ConnectionMode.parent));
    await t.pumpAndSettle();

    final bar = t.widget<BottomNavigationBar>(find.byType(BottomNavigationBar));
    expect(bar.items.map((i) => i.label), ['Con', 'Tài khoản']);

    await t.tap(navLabel('Tài khoản'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('account-email')), findsOneWidget);
    expect(find.text('me@test.vn'), findsOneWidget);
    expect(find.byKey(const Key('account-guardians')), findsOneWidget);
    expect(find.byKey(const Key('account-change-password')), findsOneWidget);
    expect(find.text('Bảo mật & khóa phụ huynh'), findsOneWidget);
    expect(find.text('Nhật ký mở khóa'), findsOneWidget);
    await t.scrollUntilVisible(find.text('Cài đặt'), 200);
    expect(find.text('Cài đặt'), findsOneWidget);
    await t.scrollUntilVisible(find.byKey(const Key('account-logout')), 200);
    expect(find.byKey(const Key('account-logout')), findsOneWidget);
    expect(find.byKey(const Key('account-delete')), findsOneWidget);
  });

  testWidgets('máy con mở app đầy đủ: vẫn Trang chủ + Cá nhân, không có khối tài khoản', (
    t,
  ) async {
    t.view.physicalSize = const Size(1080, 3600);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(await app(ConnectionMode.child));
    await t.pumpAndSettle();

    final bar = t.widget<BottomNavigationBar>(find.byType(BottomNavigationBar));
    expect(bar.items.map((i) => i.label), ['Trang chủ', 'Cá nhân']);
    await t.tap(navLabel('Cá nhân'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('account-email')), findsNothing);
    expect(find.byKey(const Key('account-logout')), findsNothing);
  });
}
