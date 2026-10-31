import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:safe_family_app/core/alerts/new_app_alerts.dart';
import 'package:safe_family_app/core/network/api_client.dart';
import 'package:safe_family_app/core/network/connection_session.dart';
import 'package:safe_family_app/core/security/secure_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemStore implements SecureStore {
  final m = <String, String>{};
  @override
  Future<String?> read(String k) async => m[k];
  @override
  Future<void> write(String k, String v) async => m[k] = v;
  @override
  Future<void> delete(String k) async => m.remove(k);
}

void main() {
  late List<Map<String, dynamic>> apps;
  late String? lastQuery;
  late NewAppAlertChecker checker;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    apps = [];
    lastQuery = null;
    final session = ConnectionSession(store: _MemStore());
    await session.setMode(ConnectionMode.parent);
    await session.saveParentTokens(access: 'a', refresh: 'r');
    final client = MockClient((req) async {
      if (req.url.path == '/api/devices') {
        return http.Response(
          jsonEncode([
            {'id': 7, 'name': 'Bé Na', 'lastSeenAt': null},
          ]),
          200,
        );
      }
      lastQuery = req.url.query;
      return http.Response.bytes(
        utf8.encode(jsonEncode(apps)),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    checker = NewAppAlertChecker(ApiClient(session: session, client: client));
  });

  Map<String, dynamic> app(int id, String label) => {
    'id': id,
    'packageName': 'com.x.a$id',
    'label': label,
    'firstSeenAt': '2026-10-31T01:00:00',
    'status': 'new',
    'decidedAt': null,
  };

  test('báo app mới đúng chữ, chỉ hỏi status=new', () async {
    apps = [app(1, 'Game vui'), app(2, 'TikTok')];
    final alerts = await checker.check();
    expect(lastQuery, 'status=new');
    expect(alerts.map((a) => a.body), [
      'Bé Na vừa cài Game vui, chờ bạn duyệt',
      'Bé Na vừa cài TikTok, chờ bạn duyệt',
    ]);
  });

  test('mỗi app chỉ báo một lần; app mới sau mốc thì báo', () async {
    apps = [app(1, 'Game vui')];
    expect(await checker.check(), hasLength(1));
    expect(await checker.check(), isEmpty);
    apps = [app(1, 'Game vui'), app(3, 'Zalo')];
    final alerts = await checker.check();
    expect(alerts, hasLength(1));
    expect(alerts.single.app.id, 3);
  });
}
