import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:safe_family_app/core/alerts/geofence_alerts.dart';
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
  late List<Map<String, dynamic>> events;
  late GeofenceAlertChecker checker;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    events = [];
    final store = _MemStore();
    final session = ConnectionSession(store: store);
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
      final after = int.parse(req.url.queryParameters['afterId']!);
      return http.Response.bytes(
        utf8.encode(
          jsonEncode([
            for (final e in events)
              if ((e['id'] as int) > after) e,
          ]),
        ),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    checker = GeofenceAlertChecker(ApiClient(session: session, client: client));
  });

  Map<String, dynamic> ev(int id, String type) => {
    'id': id,
    'geofenceName': 'Trường học',
    'type': type,
    'time': '2026-10-31T01:00:00',
  };

  test('lần đầu chỉ ghi mốc, không báo lịch sử cũ', () async {
    events = [ev(1, 'enter'), ev(2, 'exit')];
    expect(await checker.check(), isEmpty);
  });

  test('sự kiện mới sau mốc được báo đúng chữ, một lần', () async {
    events = [ev(1, 'enter')];
    await checker.check();
    events = [ev(1, 'enter'), ev(2, 'exit')];
    final alerts = await checker.check();
    expect(alerts, hasLength(1));
    expect(alerts.single.body, 'Bé Na đã rời Trường học');
    expect(await checker.check(), isEmpty);
  });
}
