import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:safe_family_app/core/alerts/tamper_alerts.dart';
import 'package:safe_family_app/core/network/api_client.dart';
import 'package:safe_family_app/core/network/child_status_text.dart';
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

AlertInfo _info(String kind, {String? detail}) =>
    AlertInfo(id: 1, kind: kind, detail: detail, createdAt: DateTime.now());

void main() {
  late List<Map<String, dynamic>> alerts;
  late List<String> queries;
  late TamperAlertChecker checker;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    alerts = [];
    queries = [];
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
      queries.add(req.url.query);
      final after = int.tryParse(req.url.queryParameters['afterId'] ?? '') ?? 0;
      return http.Response.bytes(
        utf8.encode(
          jsonEncode([
            for (final a in alerts)
              if ((a['id'] as int) > after) a,
          ]),
        ),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    checker = TamperAlertChecker(ApiClient(session: session, client: client));
  });

  Map<String, dynamic> alert(
    int id,
    String kind, {
    String? detail,
    String? readAt,
  }) => {
    'id': id,
    'kind': kind,
    'detail': detail,
    'createdAt': '2026-10-31T01:00:00',
    'readAt': readAt,
  };

  test('báo đúng chữ cho từng loại, chỉ hỏi afterId khi đã có mốc', () async {
    alerts = [
      alert(1, 'accessibility_off'),
      alert(2, 'time_changed', detail: '-120'),
    ];
    final out = await checker.check();
    expect(out.map((a) => a.body), [
      'Bé Na: Dịch vụ Trợ năng của SafeFamily đã bị tắt',
      'Bé Na: Giờ trên máy con bị chỉnh chậm hơn 120 phút',
    ]);
    expect(queries.single, ''); // chưa có mốc: lấy mới nhất
    alerts.add(alert(3, 'offline', detail: '25'));
    final next = await checker.check();
    expect(queries.last, 'afterId=2');
    expect(next.single.body, 'Bé Na: Máy con mất kết nối hơn 25 giờ');
  });

  test('mỗi cảnh báo chỉ báo một lần', () async {
    alerts = [alert(1, 'device_admin_off')];
    expect(await checker.check(), hasLength(1));
    expect(await checker.check(), isEmpty);
  });

  test('cảnh báo mẹ đã đọc thì không báo, nhưng mốc vẫn đi qua nó', () async {
    alerts = [
      alert(1, 'device_admin_off', readAt: '2026-10-31T02:00:00'),
      alert(2, 'accessibility_off'),
    ];
    final out = await checker.check();
    expect(out.map((a) => a.alert.id), [2]);
    alerts.add(alert(3, 'permission_missing', detail: 'usage_access'));
    final next = await checker.check();
    expect(queries.last, 'afterId=2');
    expect(next.map((a) => a.alert.id), [3]);
  });

  test('quá nhiều cảnh báo chưa đọc: chỉ báo vài cái mới nhất, mốc vẫn tiến tới hết', () async {
    alerts = [for (var i = 1; i <= 8; i++) alert(i, 'accessibility_off')];
    final out = await checker.check();
    expect(out.map((a) => a.alert.id), [4, 5, 6, 7, 8]);
    expect(await checker.check(), isEmpty);
  });

  test('nhãn: mã quyền, loại lạ và detail hỏng không làm sập', () {
    expect(
      alertLabel(_info('permission_missing', detail: 'usage_access')),
      contains('Máy con vừa mất quyền:'),
    );
    expect(alertLabel(_info('permission_missing')), 'Máy con vừa mất một quyền');
    expect(alertLabel(_info('time_changed', detail: 'abc')), 'Giờ trên máy con bị chỉnh');
    expect(
      alertLabel(_info('time_changed', detail: '45')),
      'Giờ trên máy con bị chỉnh nhanh hơn 45 phút',
    );
    expect(alertLabel(_info('offline', detail: '0')), 'Máy con mất kết nối');
    expect(alertLabel(_info('app_uninstall_attempt', detail: 'authorized')), contains('khóa phụ huynh'));
    expect(alertLabel(_info('app_uninstall_attempt', detail: 'guard')), contains('chưa qua khóa phụ huynh'));
    expect(alertLabel(_info('loai_la')), 'loai_la');
  });
}
