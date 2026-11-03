import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:safe_family_app/core/alerts/activity_seen.dart';
import 'package:safe_family_app/core/network/api_client.dart';
import 'package:safe_family_app/core/network/api_scope.dart';
import 'package:safe_family_app/core/network/child_status_text.dart';
import 'package:safe_family_app/core/network/connection_session.dart';
import 'package:safe_family_app/features/connection/presentation/device_activity_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/security_fakes.dart';

http.Response _json(Object? body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

String _utcAgo(Duration d) =>
    DateTime.now().toUtc().subtract(d).toIso8601String().replaceFirst('Z', '');

class _Server {
  final calls = <String>[];
  int activityStatus = 200;

  Future<http.Response> handle(http.Request r) async {
    final key = '${r.method} ${r.url.path}';
    calls.add(key);
    if (key == 'GET /api/devices/5/activity') {
      if (activityStatus != 200) return _json({'error': 'x'}, activityStatus);
      // Server trả cũ trước; màn tự đảo thành mới nhất trước.
      return _json([
        {
          'id': 1,
          'kind': 'blocked_app_open',
          'detail': 'com.google.android.youtube',
          'time': _utcAgo(const Duration(days: 2)),
        },
        {
          'id': 2,
          'kind': 'parent_auth_failed',
          'detail': null,
          'time': _utcAgo(const Duration(minutes: 20)),
        },
        {
          'id': 3,
          'kind': 'parent_unlocked',
          'detail': null,
          'time': _utcAgo(const Duration(minutes: 5)),
        },
        {'id': 4, 'kind': 'kind_la', 'time': _utcAgo(const Duration(minutes: 1))},
        {'id': 'hong', 'kind': 'parent_unlocked', 'time': 'x'},
      ]);
    }
    if (key == 'GET /api/devices/5/apps') {
      return _json([
        {
          'id': 1,
          'packageName': 'com.google.android.youtube',
          'label': 'YouTube',
          'status': 'blocked',
        },
      ]);
    }
    return _json({'error': 'không có route $key'}, 404);
  }
}

Future<(_Server, Widget)> _page() async {
  final server = _Server();
  final session = ConnectionSession(store: InMemorySecureStore());
  await session.load();
  await session.setBaseUrl('https://api.test');
  await session.saveParentTokens(access: 'a', refresh: 'r');
  final api = ApiClient(session: session, client: MockClient(server.handle));
  return (
    server,
    ApiScope(
      client: api,
      child: MaterialApp(
        home: DeviceActivityPage(device: DeviceInfo(5, 'Bé Bin', null)),
      ),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('mới nhất trước, nhóm theo ngày, hiện tên app thay tên gói', (tester) async {
    final (_, app) = await _page();
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();

    expect(find.text('Con mở YouTube (đang bị chặn)'), findsOneWidget);
    expect(find.text('Có người nhập sai khóa phụ huynh trên máy con'), findsOneWidget);
    expect(find.text('Khu phụ huynh trên máy con đã được mở khóa'), findsOneWidget);
    expect(find.text('kind_la'), findsOneWidget); // loại lạ hiện nguyên chữ
    expect(find.text('Hôm nay'), findsOneWidget);
    final tops = [
      tester.getTopLeft(find.byKey(const Key('activity-4'))).dy,
      tester.getTopLeft(find.byKey(const Key('activity-3'))).dy,
      tester.getTopLeft(find.byKey(const Key('activity-2'))).dy,
      tester.getTopLeft(find.byKey(const Key('activity-1'))).dy,
    ];
    expect(tops[0] < tops[1] && tops[1] < tops[2] && tops[2] < tops[3], isTrue);
  });

  testWidgets('dòng mới hơn mốc đã xem có chấm; mở xong thì mốc nhảy tới dòng mới nhất', (tester) async {
    SharedPreferences.setMockInitialValues({ActivitySeen.key(5): 2});
    final (_, app) = await _page();
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.fiber_manual_record), findsNWidgets(2)); // id 3, 4
    expect(await ActivitySeen.get(5), 4);
  });

  testWidgets('lỗi server: báo lỗi, không sập', (tester) async {
    final (server, app) = await _page();
    server.activityStatus = 404;
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Chưa có hoạt động nào.'), findsNothing);
  });

  test('activityLabel thiếu tên app thì hiện tên gói; dayHeading', () {
    final t = DateTime(2026, 11, 4, 14, 5);
    final a = ActivityInfo(
      id: 1,
      kind: ActivityKind.blockedAppOpen,
      detail: 'com.zing.zalo',
      time: DateTime.utc(2026),
    );
    expect(activityLabel(a), 'Con mở com.zing.zalo (đang bị chặn)');
    expect(dayHeading(t, t), 'Hôm nay');
    expect(dayHeading(t.subtract(const Duration(days: 1)), t), 'Hôm qua');
    expect(dayHeading(DateTime(2026, 10, 2), t), '02/10/2026');
  });
}
