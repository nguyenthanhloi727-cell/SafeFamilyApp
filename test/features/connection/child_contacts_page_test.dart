import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:safe_family_app/core/network/api_client.dart';
import 'package:safe_family_app/core/network/api_scope.dart';
import 'package:safe_family_app/core/network/connection_session.dart';
import 'package:safe_family_app/core/network/policy_sync.dart';
import 'package:safe_family_app/core/theme/app_theme.dart';
import 'package:safe_family_app/features/connection/presentation/child_contacts_page.dart';

import '../../helpers/security_fakes.dart';

http.Response _json(Object? body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

class _Server {
  int version = 3;
  String json =
      '{"schemaVersion":3,"timeLimit":{"enabled":true},"contacts":['
      '{"label":"Mẹ","phone":"0901234567","sos":true},'
      '{"label":"Ông","phone":"0907654321","sos":false}]}';
  final puts = <Map<String, dynamic>>[];
  int getStatus = 200;

  Future<http.Response> handle(http.Request r) async {
    if (r.url.path != '/api/devices/5/policy') return _json({}, 404);
    if (r.method == 'GET') {
      if (getStatus != 200) return _json({'error': 'Lỗi máy chủ'}, getStatus);
      return _json({'version': version, 'json': json});
    }
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    puts.add(body);
    version++;
    json = body['json'] as String;
    return _json({'version': version, 'json': json});
  }
}

Future<_Server> _pump(WidgetTester t, {int getStatus = 200}) async {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  final server = _Server()..getStatus = getStatus;
  final session = ConnectionSession(store: InMemorySecureStore());
  await session.load();
  await session.setBaseUrl('https://api.test');
  await session.setMode(ConnectionMode.parent);
  await session.saveParentTokens(access: 'a', refresh: 'r');
  await session.selectChild(5);
  final api = ApiClient(
    session: session,
    client: MockClient(server.handle),
    retryDelay: Duration.zero,
  );
  final sync = PolicySync(
    api: api,
    session: session,
    navigatorKey: GlobalKey<NavigatorState>(),
  );
  await t.pumpWidget(
    ConnectionScope(
      session: session,
      child: ApiScope(
        client: api,
        child: PolicySyncScope(
          sync: sync,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const ChildContactsPage(),
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return server;
}

void main() {
  testWidgets('hiện danh bạ của con đọc từ luật trên server', (t) async {
    await _pump(t);
    expect(find.text('Mẹ · SOS'), findsOneWidget);
    expect(find.text('Ông'), findsOneWidget);
    expect(find.text('0907654321'), findsOneWidget);
  });

  testWidgets('thêm liên hệ: ghi vào luật, giữ giới hạn thời gian', (t) async {
    final server = await _pump(t);
    await t.tap(find.byKey(const Key('child-contacts-add')));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(ChoiceChip, 'Bà'));
    await t.pump();
    await t.enterText(find.byKey(const Key('phone-field')), '090 111 2233');
    await t.tap(find.widgetWithText(FilledButton, 'Lưu'));
    await t.pumpAndSettle();

    final sent = jsonDecode(server.json) as Map<String, dynamic>;
    expect(sent['timeLimit'], {'enabled': true});
    expect(sent['contacts'], [
      {'label': 'Mẹ', 'phone': '0901234567', 'sos': true},
      {'label': 'Ông', 'phone': '0907654321', 'sos': false},
      {'label': 'Bà', 'phone': '0901112233', 'sos': false},
    ]);
    expect(server.puts.single['expectedVersion'], 3);
    expect(find.text('Bà'), findsOneWidget);
  });

  testWidgets('xóa liên hệ phải xác nhận', (t) async {
    final server = await _pump(t);
    await t.tap(find.byTooltip('Tùy chọn Ông'));
    await t.pumpAndSettle();
    await t.tap(find.text('Xóa'));
    await t.pumpAndSettle();
    expect(find.text('Xóa liên hệ Ông?'), findsOneWidget);
    await t.tap(find.widgetWithText(FilledButton, 'Xóa'));
    await t.pumpAndSettle();

    final sent = jsonDecode(server.json) as Map<String, dynamic>;
    expect((sent['contacts'] as List).map((c) => c['label']), ['Mẹ']);
    expect(find.text('Ông'), findsNothing);
  });

  testWidgets('lỗi đọc luật: báo lỗi và cho thử lại', (t) async {
    await _pump(t, getStatus: 500);
    expect(
      find.textContaining('Không đọc được danh bạ của con'),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Thử lại'), findsOneWidget);
  });
}
