import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:safe_family_app/core/alerts/request_alerts.dart';
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
  late List<Map<String, dynamic>> pending;
  late String? lastQuery;
  late ChildRequestAlertChecker checker;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    pending = [];
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
        utf8.encode(jsonEncode(pending)),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    checker = ChildRequestAlertChecker(
      ApiClient(session: session, client: client),
    );
  });

  Map<String, dynamic> req(int id, String kind, String payload) => {
    'id': id,
    'deviceId': 7,
    'kind': kind,
    'payload': payload,
    'status': 'pending',
    'createdAt': '2026-10-31T01:00:00',
    'decidedAt': null,
  };

  test('báo yêu cầu đang chờ đúng chữ, chỉ hỏi status=pending', () async {
    pending = [
      req(1, 'extra_time', '{"minutes":15}'),
      req(2, 'study_done', '{}'),
    ];
    final alerts = await checker.check();
    expect(lastQuery, 'status=pending');
    expect(alerts.map((a) => a.body), [
      'Bé Na xin thêm 15 phút',
      'Bé Na báo đã học xong, chờ bạn duyệt',
    ]);
  });

  test('mỗi yêu cầu chỉ báo một lần; yêu cầu mới sau mốc thì báo', () async {
    pending = [req(1, 'extra_time', '{"minutes":5}')];
    expect(await checker.check(), hasLength(1));
    expect(await checker.check(), isEmpty);
    pending = [req(1, 'extra_time', '{"minutes":5}'), req(3, 'study_done', '{}')];
    final alerts = await checker.check();
    expect(alerts, hasLength(1));
    expect(alerts.single.request.id, 3);
  });
}
