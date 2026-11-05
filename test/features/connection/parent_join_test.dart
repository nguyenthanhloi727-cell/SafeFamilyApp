import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:safe_family_app/core/network/api_client.dart';
import 'package:safe_family_app/core/network/api_scope.dart';
import 'package:safe_family_app/core/network/connection_session.dart';
import 'package:safe_family_app/features/connection/presentation/parent_login_page.dart';

import '../../helpers/security_fakes.dart';

void main() {
  Future<(ConnectionSession, Map<String, Object?>)> pump(
    WidgetTester t,
    http.Response Function() reply,
  ) async {
    final session = ConnectionSession(store: InMemorySecureStore());
    await session.load();
    await session.setBaseUrl('https://api.test');
    final sent = <String, Object?>{};
    final api = ApiClient(
      session: session,
      client: MockClient((req) async {
        sent[req.url.path] = jsonDecode(req.body);
        return reply();
      }),
    );
    await t.pumpWidget(
      ConnectionScope(
        session: session,
        child: ApiScope(
          client: api,
          child: const MaterialApp(home: ParentLoginPage()),
        ),
      ),
    );
    return (session, sent);
  }

  testWidgets(
    'phụ huynh thứ 2: nhập mã mời + email + mật khẩu thì vào gia đình',
    (t) async {
      final (session, sent) = await pump(
        t,
        () => http.Response(
          jsonEncode({
            'accessToken': 'a2',
            'refreshToken': 'r2',
            'familyId': 7,
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      await t.tap(find.byKey(const Key('toggle-join')));
      await t.pump();
      await t.enterText(find.byKey(const Key('join-code')), '12345678');
      await t.enterText(find.byKey(const Key('login-email')), 'bo@x.vn');
      await t.enterText(find.byKey(const Key('login-password')), 'password123');
      await t.tap(find.byKey(const Key('login-submit')));
      await t.pumpAndSettle();

      expect(sent['/api/family/join'], {
        'code': '12345678',
        'email': 'bo@x.vn',
        'password': 'password123',
      });
      expect(session.mode, ConnectionMode.parent);
      expect(session.refreshToken, 'r2');
    },
  );

  testWidgets('mã mời không đủ 8 số thì báo lỗi, không gọi server', (t) async {
    final (_, sent) = await pump(t, () => http.Response('', 500));
    await t.tap(find.byKey(const Key('toggle-join')));
    await t.pump();
    await t.enterText(find.byKey(const Key('join-code')), '123');
    await t.enterText(find.byKey(const Key('login-email')), 'bo@x.vn');
    await t.enterText(find.byKey(const Key('login-password')), 'password123');
    await t.tap(find.byKey(const Key('login-submit')));
    await t.pump();

    expect(find.byKey(const Key('login-error')), findsOneWidget);
    expect(sent, isEmpty);
  });
}
