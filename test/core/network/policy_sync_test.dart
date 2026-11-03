import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:safe_family_app/core/network/api_client.dart';
import 'package:safe_family_app/core/network/connection_session.dart';
import 'package:safe_family_app/core/network/policy_schema.dart';
import 'package:safe_family_app/core/network/policy_sync.dart';
import 'package:safe_family_app/features/profile/data/family_contact.dart';

import '../../helpers/security_fakes.dart';

http.Response _json(Object? body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

class _Server {
  int version = 0;
  String json = '{}';
  final puts = <Map<String, dynamic>>[];

  /// Số lần PUT tới sẽ bị trả 409 (giả lập nơi khác vừa sửa).
  int conflicts = 0;

  Future<http.Response> handle(http.Request r) async {
    if (r.url.path != '/api/devices/5/policy') return _json({}, 404);
    if (r.method == 'GET') return _json({'version': version, 'json': json});
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    puts.add(body);
    if (conflicts > 0) {
      conflicts--;
      version++; // nơi khác đã ghi
      return _json({'error': 'Luật đã đổi ở nơi khác.'}, 409);
    }
    if (body['expectedVersion'] != version) {
      return _json({'error': 'Luật đã đổi ở nơi khác.'}, 409);
    }
    version++;
    json = body['json'] as String;
    return _json({'version': version, 'json': json});
  }
}

Future<({_Server server, ConnectionSession session, PolicySync sync})> _setup({
  ConnectionMode mode = ConnectionMode.parent,
  int? child = 5,
}) async {
  final server = _Server();
  final session = ConnectionSession(store: InMemorySecureStore());
  await session.load();
  await session.setBaseUrl('https://api.test');
  await session.setMode(mode);
  await session.saveParentTokens(access: 'a', refresh: 'r');
  await session.selectChild(child);
  final sync = PolicySync(
    api: ApiClient(session: session, client: MockClient(server.handle)),
    session: session,
    navigatorKey: GlobalKey<NavigatorState>(),
  );
  return (server: server, session: session, sync: sync);
}

void main() {
  test(
    'PolicySchema.contactsJson: có số, tối đa 20, SOS tối đa 3, nhãn ≤30',
    () {
      FamilyContact c(
        String id,
        String phone, {
        String label = 'A',
        bool sos = true,
      }) => FamilyContact(
        id: id,
        label: label,
        phone: phone,
        order: 0,
        emergency: sos,
      );
      final out = PolicySchema.contactsJson([
        c('1', '0901234561'),
        c('2', '0901234562', sos: false), // không phải SOS nhưng vẫn là liên hệ
        c('3', ''), // không có số: bỏ
        c('4', '+84901234564', label: 'x' * 40),
        c('5', '0901234565'),
        c('6', '0901234566'), // SOS thứ 4: giữ liên hệ nhưng sos=false
      ]);
      expect(out.map((e) => e['phone']), [
        '0901234561',
        '0901234562',
        '+84901234564',
        '0901234565',
        '0901234566',
      ]);
      expect(out.map((e) => e['sos']), [true, false, true, true, false]);
      expect(out[2]['label'], 'x' * 30);
      expect(
        out.every((e) => e.keys.length == 3),
        isTrue,
      ); // không lộ id/thứ tự
      final many = PolicySchema.contactsJson([
        for (var i = 0; i < 25; i++) c('$i', '090123${4500 + i}', sos: false),
      ]);
      expect(many.length, PolicySchema.maxContacts);
    },
  );

  test('blockedIn / timeLimitIn đọc đúng và chịu được JSON hỏng', () {
    const json =
        '{"timeLimit":{"enabled":true},"appLock":{"blocked":["a","b",3]}}';
    expect(PolicySync.blockedIn(json), {'a', 'b'});
    expect(PolicySync.timeLimitIn(json), '{"enabled":true}');
    expect(PolicySync.blockedIn('không phải json'), isEmpty);
    expect(PolicySync.timeLimitIn('{}'), isNull);
  });

  testWidgets(
    'setBlocked: chỉ sửa appLock.blocked của máy con, giữ phần còn lại',
    (t) async {
      final s = await _setup();
      s.server.version = 2;
      s.server.json = '{"schemaVersion":2,"timeLimit":{"enabled":true},"appLock":{"blocked":["b.app"],"schedules":[]},"contacts":[]}';

      final after = await t.runAsync(
        () => s.sync.setBlocked(5, 'com.google.android.youtube', true),
      );
      expect(after, {'b.app', 'com.google.android.youtube'});
      expect(s.server.puts.single['expectedVersion'], 2);
      final sent = jsonDecode(s.server.json) as Map<String, dynamic>;
      expect(sent['appLock']['blocked'], [
        'b.app',
        'com.google.android.youtube',
      ]);
      expect(sent['timeLimit'], {'enabled': true});
      expect(s.session.policyVersionOf(5), 3);

      final removed = await t.runAsync(
        () => s.sync.setBlocked(5, 'b.app', false),
      );
      expect(removed, {'com.google.android.youtube'});
    },
  );

  testWidgets('setBlocked khi server chưa có luật: tạo luật chỉ có appLock', (
    t,
  ) async {
    final s = await _setup();
    await t.runAsync(() => s.sync.setBlocked(5, 'a.app', true));
    expect(s.server.puts.single['expectedVersion'], 0);
    final sent = jsonDecode(s.server.json) as Map<String, dynamic>;
    expect(sent['appLock']['blocked'], ['a.app']);
    expect(sent.containsKey('timeLimit'), isFalse);
  });

  testWidgets('setTimeLimit: ghi timeLimit, giữ danh sách chặn', (t) async {
    final s = await _setup();
    s.server.version = 1;
    s.server.json =
        '{"schemaVersion":2,"appLock":{"blocked":["x.app"],"schedules":[]}}';
    await t.runAsync(
      () => s.sync.setTimeLimit(5, '{"enabled":true,"total":[60]}'),
    );
    final sent = jsonDecode(s.server.json) as Map<String, dynamic>;
    expect(sent['timeLimit'], {
      'enabled': true,
      'total': [60],
    });
    expect(sent['appLock']['blocked'], ['x.app']);
  });

  testWidgets('lệch phiên bản (409): đọc lại và ghi lại, không ghi đè mù', (
    t,
  ) async {
    final s = await _setup();
    s.server.conflicts = 1;
    await t.runAsync(() => s.sync.setBlocked(5, 'a.app', true));
    expect(s.server.puts, hasLength(2));
    expect(s.server.puts.last['expectedVersion'], 1);
    expect(PolicySync.blockedIn(s.server.json), {'a.app'});
  });

  testWidgets('409 liên tục: ném ApiException, không treo', (t) async {
    final s = await _setup();
    s.server.conflicts = 5;
    final error = await t.runAsync(() async {
      try {
        await s.sync.setBlocked(5, 'a.app', true);
        return null;
      } on ApiException catch (e) {
        return e;
      }
    });
    expect(error?.isConflict, isTrue);
    expect(s.server.puts, hasLength(2));
  });

  test('contactsIn: đọc danh bạ, thiếu sos theo schema, bỏ mục hỏng', () {
    final v3 = PolicySync.contactsIn(
      '{"schemaVersion":3,"contacts":[{"label":"Mẹ","phone":"0901234567","sos":true},'
      '{"label":"Ông","phone":"0907654321"},{"label":1,"phone":"x"},"hỏng"]}',
    );
    expect(v3.map((c) => c.label), ['Mẹ', 'Ông']);
    expect(v3.map((c) => c.emergency), [true, false]);
    final v2 = PolicySync.contactsIn(
      '{"schemaVersion":2,"contacts":[{"label":"Mẹ","phone":"0901234567"}]}',
    );
    expect(v2.single.emergency, isTrue, reason: 'schema 2: mọi số đều là SOS');
    expect(PolicySync.contactsIn('không phải json'), isEmpty);
    expect(PolicySync.contactsIn('{}'), isEmpty);
  });

  testWidgets(
    'setContacts: chỉ đổi contacts, lên schema 3, giữ giới hạn và danh sách chặn',
    (t) async {
      final s = await _setup();
      s.server.version = 1;
      s.server.json =
          '{"schemaVersion":1,"timeLimit":{"enabled":true},"appLock":{"blocked":["x.app"],"schedules":[]}}';

      final saved = await t.runAsync(
        () => s.sync.setContacts(5, [
          const FamilyContact(
            id: 'a',
            label: 'Mẹ',
            phone: '0901234567',
            order: 0,
            emergency: true,
          ),
          const FamilyContact(
            id: 'b',
            label: 'Ông',
            phone: '0907654321',
            order: 1,
          ),
        ]),
      );
      final sent = jsonDecode(s.server.json) as Map<String, dynamic>;
      expect(sent['schemaVersion'], 3);
      expect(sent['timeLimit'], {'enabled': true});
      expect(sent['appLock']['blocked'], ['x.app']);
      expect(sent['contacts'], [
        {'label': 'Mẹ', 'phone': '0901234567', 'sos': true},
        {'label': 'Ông', 'phone': '0907654321', 'sos': false},
      ]);
      expect(saved!.map((c) => c.emergency), [true, false]);
      expect((await t.runAsync(() => s.sync.loadContacts(5)))!.length, 2);
    },
  );

  testWidgets('mất mạng: setContacts ném ApiException, không treo', (t) async {
    final s = await _setup();
    final offline = PolicySync(
      api: ApiClient(
        session: s.session,
        client: MockClient((_) async => throw http.ClientException('offline')),
        retryDelay: Duration.zero,
      ),
      session: s.session,
      navigatorKey: GlobalKey<NavigatorState>(),
    );
    final error = await t.runAsync(() async {
      try {
        await offline.setContacts(5, const []);
        return null;
      } on ApiException catch (e) {
        return e;
      }
    });
    expect(error, isNotNull);
  });
}
