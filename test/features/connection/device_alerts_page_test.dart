import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:safe_family_app/core/network/api_client.dart';
import 'package:safe_family_app/core/network/api_scope.dart';
import 'package:safe_family_app/core/network/connection_session.dart';
import 'package:safe_family_app/features/connection/presentation/device_alerts_page.dart';

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
  final read = <int>{};
  int readStatus = 200;

  Future<http.Response> handle(http.Request r) async {
    final key = '${r.method} ${r.url.path}';
    calls.add(key);
    if (key == 'GET /api/devices/5/alerts') {
      // Server trả cũ trước; màn tự đảo thành mới nhất trước.
      return _json([
        {
          'id': 1,
          'kind': 'offline',
          'detail': '26',
          'createdAt': _utcAgo(const Duration(hours: 5)),
          'readAt': _utcAgo(const Duration(hours: 4)),
        },
        {
          'id': 2,
          'kind': 'accessibility_off',
          'detail': null,
          'createdAt': _utcAgo(const Duration(minutes: 30)),
          'readAt': read.contains(2) ? _utcAgo(const Duration(minutes: 1)) : null,
        },
        {
          'id': 3,
          'kind': 'time_changed',
          'detail': '-90',
          'createdAt': _utcAgo(const Duration(minutes: 5)),
          'readAt': read.contains(3) ? _utcAgo(const Duration(minutes: 1)) : null,
        },
      ]);
    }
    final m = RegExp(r'^POST /api/alerts/(\d+)/read$').firstMatch(key);
    if (m != null) {
      if (readStatus != 200) return _json({'error': 'x'}, readStatus);
      read.add(int.parse(m.group(1)!));
      return _json({'id': int.parse(m.group(1)!)});
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
        home: DeviceAlertsPage(device: DeviceInfo(5, 'Bé Bin', null)),
      ),
    ),
  );
}

void main() {
  testWidgets('liệt kê mới nhất trước, chưa đọc có chấm, không hiện nội dung nào khác', (tester) async {
    final (server, app) = await _page();
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();

    expect(find.text('Giờ trên máy con bị chỉnh chậm hơn 90 phút'), findsOneWidget);
    expect(find.text('Dịch vụ Trợ năng của SafeFamily đã bị tắt'), findsOneWidget);
    expect(find.text('Máy con mất kết nối hơn 26 giờ'), findsOneWidget);
    final tops = [
      tester.getTopLeft(find.byKey(const Key('alert-3'))).dy,
      tester.getTopLeft(find.byKey(const Key('alert-2'))).dy,
      tester.getTopLeft(find.byKey(const Key('alert-1'))).dy,
    ];
    expect(tops[0] < tops[1] && tops[1] < tops[2], isTrue);
    expect(find.byIcon(Icons.fiber_manual_record), findsNWidgets(2)); // 2 chưa đọc
    expect(server.calls.where((c) => c.startsWith('POST')), isEmpty);
  });

  testWidgets('chạm một cảnh báo chưa đọc thì đánh dấu đã đọc, không cần khóa phụ huynh', (tester) async {
    final (server, app) = await _page();
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('alert-3')));
    await tester.pumpAndSettle();

    expect(server.calls, contains('POST /api/alerts/3/read'));
    expect(find.byIcon(Icons.fiber_manual_record), findsOneWidget);
  });

  testWidgets('"Đã đọc hết" đánh dấu mọi cảnh báo chưa đọc rồi nút biến mất', (tester) async {
    final (server, app) = await _page();
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('alerts-mark-all')));
    await tester.pumpAndSettle();

    expect(server.read, {2, 3});
    expect(find.byKey(const Key('alerts-mark-all')), findsNothing);
    expect(find.byIcon(Icons.fiber_manual_record), findsNothing);
  });

  testWidgets('lỗi server khi đánh dấu: báo lỗi, không sập', (tester) async {
    final (server, app) = await _page();
    server.readStatus = 404;
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('alert-2')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('alert-2')), findsOneWidget);
  });
}
