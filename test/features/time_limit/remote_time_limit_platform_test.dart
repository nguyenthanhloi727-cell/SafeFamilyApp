import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:safe_family_app/core/network/api_client.dart';
import 'package:safe_family_app/core/network/connection_session.dart';
import 'package:safe_family_app/core/network/policy_sync.dart';
import 'package:safe_family_app/features/time_limit/data/remote_time_limit_platform.dart';
import 'package:safe_family_app/features/time_limit/domain/time_limit_config.dart';

import '../../helpers/security_fakes.dart';

http.Response _ok(Object? body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json'},
);

void main() {
  late int version;
  late String policy;
  late List<http.Request> sent;
  late RemoteTimeLimitPlatform platform;

  setUp(() async {
    version = 1;
    policy =
        '{"schemaVersion":2,"timeLimit":{"enabled":true,"total":[90,90,90,90,90,90,90],"apps":{}},'
        '"appLock":{"blocked":["x.app"],"schedules":[]}}';
    sent = [];
    final session = ConnectionSession(store: InMemorySecureStore());
    await session.load();
    await session.setBaseUrl('https://api.test');
    await session.setMode(ConnectionMode.parent);
    await session.saveParentTokens(access: 'a', refresh: 'r');
    final api = ApiClient(
      session: session,
      client: MockClient((r) async {
        sent.add(r);
        final path = r.url.path;
        if (path == '/api/devices/5/policy') {
          if (r.method == 'GET') return _ok({'version': version, 'json': policy});
          final body = jsonDecode(r.body) as Map<String, dynamic>;
          version++;
          policy = body['json'] as String;
          return _ok({'version': version, 'json': policy});
        }
        if (path == '/api/devices/5/usage') {
          return _ok([
            {
              'date': '2026-11-04',
              'totalMinutes': 50,
              'blocks': 0,
              'apps': {'x.app': 50},
            },
          ]);
        }
        if (path == '/api/devices/5/apps') {
          return _ok([
            {'id': 1, 'packageName': 'x.app', 'label': 'Game X', 'status': 'allowed'},
          ]);
        }
        return _ok({
          'id': 1,
          'type': 'x',
          'payloadJson': '{}',
          'createdAt': '2026-01-01T00:00:00Z',
        });
      }),
    );
    platform = RemoteTimeLimitPlatform(
      api: api,
      sync: PolicySync(
        api: api,
        session: session,
        navigatorKey: GlobalKey<NavigatorState>(),
      ),
      childId: 5,
    );
  });

  test('load đọc giới hạn từ luật của máy con', () async {
    final config = await platform.load();
    expect(config.enabled, isTrue);
    expect(config.totalFor(1), 90);
  });

  test('save chỉ đổi timeLimit trong luật máy con, giữ danh sách chặn', () async {
    final config = (await platform.load()).copyWith(
      total: List<int?>.filled(7, 30),
    );
    await platform.save(config);
    final saved = jsonDecode(policy) as Map<String, dynamic>;
    expect((saved['timeLimit'] as Map)['total'], List.filled(7, 30));
    expect(saved['appLock']['blocked'], ['x.app']);
    expect(TimeLimitConfig.fromJson(PolicySync.timeLimitIn(policy)!).totalFor(2), 30);
  });

  test('số liệu hôm nay lấy từ báo cáo của máy con', () async {
    final usage = await platform.usageToday();
    expect(usage?.totalMinutes, 50);
    expect(usage?.apps, {'x.app': 50});
    expect(await platform.appLabels(['x.app']), {'x.app': 'Game X'});
  });

  test('thêm giờ và giờ học gửi thành lệnh cho máy con', () async {
    expect(await platform.addBonus(15), 15);
    await platform.startStudy(30);
    await platform.setTotalLimitDisabledToday(true);
    final types = [
      for (final r in sent.where((r) => r.url.path == '/api/devices/5/commands'))
        (jsonDecode(r.body) as Map<String, dynamic>)['type'],
    ];
    expect(types, ['extra_time_grant', 'study_start', 'disable_limit_today']);
    expect(() => platform.setStudyDisabledToday(true), throwsUnsupportedError);
  });
}
