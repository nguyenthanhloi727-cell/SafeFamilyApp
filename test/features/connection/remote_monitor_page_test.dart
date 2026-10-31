import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:safe_family_app/core/network/api_client.dart';
import 'package:safe_family_app/core/network/api_scope.dart';
import 'package:safe_family_app/core/network/connection_session.dart';
import 'package:safe_family_app/features/connection/presentation/remote_monitor_page.dart';

import '../../helpers/security_fakes.dart';

http.Response _json(Object? body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

class _Server {
  int fenceVersion = 1;
  List<Map<String, dynamic>> fences = [
    {'id': 1, 'name': 'Trường', 'lat': 10.77, 'lng': 106.7, 'radiusM': 150.0},
  ];
  final requests = <String>[];
  final bodies = <String, Object?>{};

  Future<http.Response> handle(http.Request r) async {
    final key = '${r.method} ${r.url.path}';
    requests.add(key);
    if (r.body.isNotEmpty) bodies[key] = jsonDecode(r.body);
    switch (key) {
      case 'GET /api/devices/5/location':
        return _json({
          'lat': 10.77,
          'lng': 106.7,
          'accuracy': 12,
          // Server trả giờ UTC không có "Z".
          'time': DateTime.now()
              .toUtc()
              .subtract(const Duration(minutes: 3))
              .toIso8601String()
              .replaceFirst('Z', ''),
        });
      case 'GET /api/devices/5/geofences':
        return _json({'version': fenceVersion, 'geofences': fences});
      case 'GET /api/devices/5/geofence-events':
        return _json([
          {
            'id': 9,
            'geofenceId': 1,
            'geofenceName': 'Trường',
            'type': 'exit',
            'time': DateTime.now().toUtc().toIso8601String(),
          },
        ]);
      case 'PUT /api/devices/5/geofences':
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        if (body['expectedVersion'] != fenceVersion) {
          return _json({'error': 'Hàng rào đã đổi ở nơi khác.'}, 409);
        }
        fenceVersion++;
        fences = [
          for (final (i, f)
              in (body['geofences'] as List<dynamic>).cast<Map<String, dynamic>>().indexed)
            {...f, 'id': i + 1},
        ];
        return _json({'version': fenceVersion, 'geofences': fences});
      case 'POST /api/devices/5/commands':
        return _json({
          'id': 1,
          'type': 'lock',
          'payloadJson': '{}',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        });
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
    MaterialApp(
      home: ApiScope(
        client: api,
        child: RemoteMonitorPage(
          device: DeviceInfo(5, 'Bé Bin', null),
          refreshEvery: const Duration(hours: 1),
        ),
      ),
    ),
  );
}

void main() {
  test('parseServerTime coi giờ không kèm múi giờ là UTC', () {
    expect(parseServerTime('2026-10-31T07:25:32')!.isUtc, isTrue);
    expect(parseServerTime('2026-10-31T07:25:32Z')!.isUtc, isTrue);
    expect(
      parseServerTime('2026-10-31T14:25:32+07:00'),
      DateTime.utc(2026, 10, 31, 7, 25, 32),
    );
    expect(parseServerTime(null), isNull);
  });

  testWidgets('hiện vị trí cuối, hàng rào và sự kiện rời khu vực', (t) async {
    final (_, app) = await _page();
    await t.pumpWidget(app);
    await t.pumpAndSettle();

    expect(find.byKey(const Key('last-location')), findsOneWidget);
    expect(find.textContaining('3 phút trước'), findsOneWidget);
    expect(find.text('Trường'), findsOneWidget);
    expect(find.text('Con đã rời Trường'), findsOneWidget);
  });

  testWidgets('thêm hàng rào gửi PUT kèm phiên bản hiện tại', (t) async {
    final (server, app) = await _page();
    await t.pumpWidget(app);
    await t.pumpAndSettle();

    await t.tap(find.byKey(const Key('add-fence')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('fence-use-last')));
    await t.enterText(find.byKey(const Key('fence-name')), 'Nhà ông bà');
    await t.tap(find.byKey(const Key('fence-save')));
    await t.pumpAndSettle();

    final body = server.bodies['PUT /api/devices/5/geofences']! as Map;
    expect(body['expectedVersion'], 1);
    final sent = (body['geofences'] as List).cast<Map>();
    expect(sent.map((f) => f['name']), ['Trường', 'Nhà ông bà']);
    expect(find.text('Nhà ông bà'), findsOneWidget);
  });

  testWidgets('bán kính dưới 100 m bị từ chối, không gọi server', (t) async {
    final (server, app) = await _page();
    await t.pumpWidget(app);
    await t.pumpAndSettle();

    await t.tap(find.byKey(const Key('add-fence')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('fence-name')), 'A');
    await t.enterText(find.byKey(const Key('fence-lat')), '10.5');
    await t.enterText(find.byKey(const Key('fence-lng')), '106.5');
    await t.enterText(find.byKey(const Key('fence-radius')), '50');
    await t.tap(find.byKey(const Key('fence-save')));
    await t.pumpAndSettle();

    expect(find.textContaining('Bán kính từ 100 m'), findsOneWidget);
    expect(server.requests, isNot(contains('PUT /api/devices/5/geofences')));
  });

  testWidgets('bấm Khóa gửi lệnh lock kèm số phút', (t) async {
    final (server, app) = await _page();
    await t.pumpWidget(app);
    await t.pumpAndSettle();

    await t.ensureVisible(find.byKey(const Key('cmd-lock')));
    await t.tap(find.byKey(const Key('cmd-lock')));
    await t.pumpAndSettle();

    final body = server.bodies['POST /api/devices/5/commands']! as Map;
    expect(body['type'], 'lock');
    expect(jsonDecode(body['payloadJson'] as String), {'minutes': 60});
  });
}
