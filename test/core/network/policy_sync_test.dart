import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:safe_family_app/core/network/api_client.dart';
import 'package:safe_family_app/core/network/connection_session.dart';
import 'package:safe_family_app/core/network/policy_schema.dart';
import 'package:safe_family_app/core/network/policy_sync.dart';

import '../../helpers/security_fakes.dart';

http.Response _json(Object? body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

const _timeLimit = '{"enabled":true,"total":[60,60,60,60,60,60,60],"apps":{}}';

class _Server {
  int version = 0;
  String json = '{}';
  final puts = <Map<String, dynamic>>[];

  Future<http.Response> handle(http.Request r) async {
    if (r.url.path != '/api/devices/5/policy') return _json({}, 404);
    if (r.method == 'GET') return _json({'version': version, 'json': json});
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    puts.add(body);
    if (body['expectedVersion'] != version) {
      return _json({'error': 'Luật đã đổi ở nơi khác.'}, 409);
    }
    version++;
    json = body['json'] as String;
    return _json({'version': version, 'json': json});
  }
}

Future<
  ({
    _Server server,
    ConnectionSession session,
    PolicySync sync,
    Set<String> blocked,
    Widget app,
  })
>
_setup({ConnectionMode mode = ConnectionMode.parent, int? child = 5}) async {
  final server = _Server();
  final session = ConnectionSession(store: InMemorySecureStore());
  await session.load();
  await session.setBaseUrl('https://api.test');
  await session.setMode(mode);
  await session.saveParentTokens(access: 'a', refresh: 'r');
  await session.selectChild(child);
  final key = GlobalKey<NavigatorState>();
  final blocked = <String>{'com.google.android.youtube'};
  final sync = PolicySync(
    api: ApiClient(session: session, client: MockClient(server.handle)),
    session: session,
    navigatorKey: key,
    loadTimeLimit: () async => _timeLimit,
    blockedPackages: () => blocked,
    debounce: const Duration(milliseconds: 10),
  );
  return (
    server: server,
    session: session,
    sync: sync,
    blocked: blocked,
    app: MaterialApp(
      navigatorKey: key,
      home: const Scaffold(body: SizedBox()),
    ),
  );
}

void main() {
  test('PolicySchema.build: có schemaVersion, appLock.blocked đã sắp xếp', () {
    final json = jsonDecode(
      PolicySchema.build(
        timeLimit: {'enabled': true},
        blocked: ['b.app', 'a.app', 'b.app'],
      ),
    );
    expect(json['schemaVersion'], 1);
    expect(json['timeLimit'], {'enabled': true});
    expect(json['appLock'], {
      'blocked': ['a.app', 'b.app'],
      'schedules': [],
    });
  });

  test('PolicySchema.sameContent bỏ qua thứ tự khóa và khoảng trắng', () {
    expect(PolicySchema.sameContent('{"a":1,"b":[1,2]}', '{ "b":[1,2], "a":1 }'),
        isTrue);
    expect(PolicySchema.sameContent('{"a":1}', '{"a":2}'), isFalse);
    expect(PolicySchema.sameContent('không phải json', '{}'), isFalse);
  });

  testWidgets('không làm gì khi không phải máy mẹ hoặc chưa chọn máy con', (
    t,
  ) async {
    final local = await _setup(mode: ConnectionMode.local);
    expect(await local.sync.pushNow(), PolicyPushResult.skipped);
    final noChild = await _setup(child: null);
    expect(await noChild.sync.pushNow(), PolicyPushResult.skipped);
    expect(local.server.puts, isEmpty);
    expect(noChild.server.puts, isEmpty);
  });

  testWidgets('lần đầu (server chưa có luật) gửi expectedVersion 0 rồi nhớ phiên bản', (
    t,
  ) async {
    final s = await _setup();
    await t.pumpWidget(s.app);

    final result = await s.sync.pushNow();
    expect(result, PolicyPushResult.pushed);
    expect(s.server.puts.single['expectedVersion'], 0);
    final sent = jsonDecode(s.server.puts.single['json'] as String);
    expect(sent['schemaVersion'], 1);
    expect(sent['appLock']['blocked'], ['com.google.android.youtube']);
    expect(sent['timeLimit']['enabled'], isTrue);
    expect(s.session.policyVersionOf(5), 1);
  });

  testWidgets('changed() gom nhiều lần sửa thành một lần gửi', (t) async {
    final s = await _setup();
    await t.pumpWidget(s.app);
    s.sync
      ..changed()
      ..changed()
      ..changed();
    await t.pump(const Duration(milliseconds: 200));
    await t.pump();
    expect(s.server.puts, hasLength(1));
  });

  testWidgets('409 và server khác máy mẹ: hỏi, "Giữ" thì không ghi đè', (t) async {
    final s = await _setup();
    await t.pumpWidget(s.app);
    await s.sync.pushNow(); // v1
    s.server.version = 4; // nơi khác đổi
    s.server.json = '{"schemaVersion":1,"timeLimit":{"enabled":false}}';
    s.server.puts.clear();

    final future = s.sync.pushNow();
    await t.pumpAndSettle();
    expect(find.text('Luật trên máy con đã đổi ở nơi khác'), findsOneWidget);
    await t.tap(find.byKey(const Key('policy-keep-server')));
    await t.pumpAndSettle();

    expect(await future, PolicyPushResult.keptServer);
    // Chỉ có lần PUT lệch phiên bản (bị 409); không có lần PUT ghi đè nào.
    expect(s.server.puts, hasLength(1));
    expect(s.server.version, 4);
    expect(s.server.json, contains('"enabled":false'));
    expect(s.session.policyVersionOf(5), 4);
  });

  testWidgets('409 rồi mẹ chọn "Ghi đè": PUT lại với phiên bản server', (t) async {
    final s = await _setup();
    await t.pumpWidget(s.app);
    await s.sync.pushNow();
    s.server.version = 4;
    s.server.json = '{"schemaVersion":1,"timeLimit":{"enabled":false}}';
    s.server.puts.clear();

    final future = s.sync.pushNow();
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('policy-overwrite')));
    await t.pumpAndSettle();

    expect(await future, PolicyPushResult.pushed);
    expect(s.server.puts.last['expectedVersion'], 4);
    expect(s.server.version, 5);
    expect(s.session.policyVersionOf(5), 5);
  });

  testWidgets('409 nhưng server đã có đúng luật này: không hỏi, không ghi đè', (
    t,
  ) async {
    final s = await _setup();
    await t.pumpWidget(s.app);
    await s.sync.pushNow();
    s.server.version = 3; // ai đó gửi đúng luật y hệt
    s.server.puts.clear();

    final result = await s.sync.pushNow();
    await t.pumpAndSettle();
    expect(find.byKey(const Key('policy-overwrite')), findsNothing);
    expect(result, PolicyPushResult.pushed);
    expect(s.server.puts, hasLength(1)); // chỉ lần bị 409
    expect(s.session.policyVersionOf(5), 3);
  });

  testWidgets('mất mạng: báo failed, không ném lỗi', (t) async {
    final s = await _setup();
    final offline = PolicySync(
      api: ApiClient(
        session: s.session,
        client: MockClient((_) async => throw http.ClientException('offline')),
        retryDelay: Duration.zero,
      ),
      session: s.session,
      navigatorKey: GlobalKey<NavigatorState>(),
      loadTimeLimit: () async => _timeLimit,
      blockedPackages: () => {},
    );
    expect(await t.runAsync(offline.pushNow), PolicyPushResult.failed);
  });
}
