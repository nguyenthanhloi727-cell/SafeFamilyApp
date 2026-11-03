import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:safe_family_app/core/network/api_client.dart';
import 'package:safe_family_app/core/network/api_scope.dart';
import 'package:safe_family_app/core/network/connection_session.dart';
import 'package:safe_family_app/core/theme/app_theme.dart';
import 'package:safe_family_app/features/home/presentation/home_page.dart';

import '../../helpers/security_fakes.dart';

void main() {
  Future<(ConnectionSession, Widget)> setup(
    List<Map<String, Object?>> devices,
  ) async {
    final session = ConnectionSession(store: InMemorySecureStore());
    await session.load();
    await session.setBaseUrl('https://api.test');
    await session.setMode(ConnectionMode.parent);
    await session.saveParentTokens(access: 'a', refresh: 'r');
    final client = MockClient((r) async {
      final body = r.url.path == '/api/devices' ? devices : <Object?>[];
      return http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    return (
      session,
      ConnectionScope(
        session: session,
        child: ApiScope(
          client: ApiClient(session: session, client: client),
          child: MaterialApp(theme: AppTheme.light, home: const HomePage()),
        ),
      ),
    );
  }

  testWidgets('máy mẹ: Trang chủ có thẻ máy con và các lối tắt quản lý', (
    t,
  ) async {
    final (session, app) = await setup([
      {'id': 5, 'name': 'Bé Na', 'lastSeenAt': null},
    ]);
    await t.pumpWidget(app);
    await t.pumpAndSettle();

    expect(session.selectedChildId, 5, reason: 'chỉ một máy con thì chọn luôn');
    expect(find.text('Bé Na'), findsOneWidget);
    expect(find.byKey(const Key('home-block-apps')), findsOneWidget);
    expect(find.byKey(const Key('home-time-limit')), findsOneWidget);
    expect(find.byKey(const Key('home-requests')), findsOneWidget);
    expect(find.text('Đang cản trở'), findsNothing);
  });

  testWidgets('máy mẹ chưa ghép máy con: mời ghép đôi', (t) async {
    final (_, app) = await setup([]);
    await t.pumpWidget(app);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('home-pair-child')), findsOneWidget);
    expect(find.byKey(const Key('home-block-apps')), findsNothing);
  });
}
