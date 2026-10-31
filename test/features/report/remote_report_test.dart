import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:safe_family_app/core/network/api_client.dart';
import 'package:safe_family_app/core/network/api_scope.dart';
import 'package:safe_family_app/core/network/connection_session.dart';
import 'package:safe_family_app/core/theme/app_theme.dart';
import 'package:safe_family_app/features/report/presentation/remote_report_view.dart';
import 'package:safe_family_app/features/report/presentation/report_page.dart';
import 'package:safe_family_app/features/time_limit/data/time_limit_platform.dart';

import '../../helpers/security_fakes.dart';

http.Response _json(Object? body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

/// Hôm nay là thứ Bảy 31/10/2026.
final _today = DateTime(2026, 10, 31);

class _Server {
  final calls = <String>[];
  bool usageFails = false;
  bool noDevices = false;
  bool empty = false;

  Future<http.Response> handle(http.Request r) async {
    calls.add('${r.method} ${r.url.path}'
        '${r.url.query.isEmpty ? '' : '?${r.url.query}'}');
    final path = r.url.path;
    if (path == '/api/devices') {
      if (noDevices) return _json({'error': 'x'}, 500);
      return _json([
        {'id': 5, 'name': 'Bé Bin', 'pairedAt': '2026-10-01T00:00:00Z'},
        {'id': 6, 'name': 'Bé Na', 'pairedAt': '2026-10-01T00:00:00Z'},
      ]);
    }
    if (path.endsWith('/usage')) {
      if (usageFails) return _json({'error': 'Không tìm thấy.'}, 404);
      if (empty) return _json([]);
      final id = path.split('/')[3];
      if (id == '6') {
        return _json([
          {'date': '2026-10-31', 'totalMinutes': 15, 'blocks': 0, 'apps': {'com.na.app': 15}},
        ]);
      }
      return _json([
        {'date': '2026-10-30', 'totalMinutes': 90, 'blocks': 2, 'apps': {'com.google.android.youtube': 60, 'com.zing.zalo': 30}},
        {'date': '2026-10-31', 'totalMinutes': 80, 'blocks': 1, 'apps': {'com.google.android.youtube': 80}},
        {'date': 'hỏng', 'totalMinutes': 1, 'apps': {}},
      ]);
    }
    if (path.endsWith('/apps')) {
      return _json([
        {'id': 1, 'packageName': 'com.google.android.youtube', 'label': 'YouTube', 'status': 'allowed'},
      ]);
    }
    return _json({'error': 'không có route $path'}, 404);
  }
}

class _NoLocal implements TimeLimitPlatform {
  @override
  dynamic noSuchMethod(Invocation i) =>
      throw StateError('không được đụng máy này');
}

Future<(_Server, Widget)> _app({int? target, int? remoteId}) async {
  final server = _Server();
  final session = ConnectionSession(store: InMemorySecureStore());
  await session.load();
  await session.setBaseUrl('https://api.test');
  await session.setMode(ConnectionMode.parent);
  await session.saveParentTokens(access: 'a', refresh: 'r');
  await session.selectChild(target);
  final api = ApiClient(session: session, client: MockClient(server.handle));
  return (
    server,
    ConnectionScope(
      session: session,
      child: ApiScope(
        client: api,
        child: MaterialApp(
          theme: AppTheme.light,
          home: ReportPage(
            platform: _NoLocal(),
            now: () => _today,
            remoteDevice: remoteId == null ? null : DeviceInfo(remoteId, 'Bé Bin', null),
          ),
        ),
      ),
    ),
  );
}

void main() {
  test('remoteWeek: đủ 7 ngày, ngày thiếu là 0 phút', () {
    final week = remoteWeek([
      UsageDayInfo(date: DateTime(2026, 10, 30), totalMinutes: 90, blocks: 2, apps: const {'a.b': 90}),
      UsageDayInfo(date: DateTime(2026, 10, 31), totalMinutes: 80),
    ], _today);
    expect(week, hasLength(7));
    expect(week.first.date, DateTime(2026, 10, 25));
    expect(week.last.date, DateTime(2026, 10, 31));
    expect(week.map((d) => d.totalMinutes), [0, 0, 0, 0, 0, 90, 80]);
    expect(week[5].apps['a.b'], 90);
    expect(week[5].blocks, 2);
  });

  testWidgets('chế độ mẹ đã chọn máy con: đọc server, không đụng máy này', (t) async {
    t.view.physicalSize = const Size(800, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final (server, app) = await _app(target: 5);
    await t.pumpWidget(app);
    await t.pumpAndSettle();

    expect(server.calls, contains('GET /api/devices/5/usage?from=2026-10-25&to=2026-10-31'));
    expect(find.byKey(const Key('report-chart')), findsOneWidget);
    expect(find.text('1 giờ 20 phút'), findsOneWidget); // hôm nay = 80 phút
    expect(find.text('YouTube'), findsOneWidget); // nhãn từ danh sách app
    expect(find.text('com.zing.zalo'), findsOneWidget); // không có nhãn thì hiện tên gói
    expect(find.text('Con chạm vào app bị chặn 3 lần'), findsOneWidget);
    expect(find.text('Tổng: 2 giờ 50 phút'), findsOneWidget);
  });

  testWidgets('truyền remoteDevice thì đọc máy đó dù chưa chọn máy con', (t) async {
    final (server, app) = await _app(remoteId: 5);
    await t.pumpWidget(app);
    await t.pumpAndSettle();
    expect(server.calls.any((c) => c.startsWith('GET /api/devices/5/usage')), isTrue);
  });

  testWidgets('có nhiều máy con thì chọn được; đổi máy tải lại số liệu', (t) async {
    final (server, app) = await _app(target: 5);
    await t.pumpWidget(app);
    await t.pumpAndSettle();

    await t.tap(find.byKey(const Key('report-device')));
    await t.pumpAndSettle();
    await t.tap(find.text('Bé Na').last);
    await t.pumpAndSettle();

    expect(server.calls.any((c) => c.startsWith('GET /api/devices/6/usage')), isTrue);
    expect(find.text('com.na.app'), findsOneWidget);
    expect(find.text('YouTube'), findsNothing);
  });

  testWidgets('máy con chưa báo gì: nói rõ, không vẽ biểu đồ', (t) async {
    final (server, app) = await _app(target: 5);
    server.empty = true;
    await t.pumpWidget(app);
    await t.pumpAndSettle();
    expect(find.text('Chưa có số liệu'), findsOneWidget);
    expect(find.byKey(const Key('report-chart')), findsNothing);
  });

  testWidgets('lỗi server: báo lỗi và có nút thử lại, không sập', (t) async {
    final (server, app) = await _app(target: 5);
    server.usageFails = true;
    await t.pumpWidget(app);
    await t.pumpAndSettle();
    expect(find.text('Không tải được báo cáo'), findsOneWidget);
    expect(find.text('Thử lại'), findsOneWidget);

    server.usageFails = false;
    await t.tap(find.text('Thử lại'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('report-chart')), findsOneWidget);
  });

  testWidgets('lỗi tải danh sách máy: vẫn xem được máy đang chọn', (t) async {
    final (server, app) = await _app(target: 5);
    server.noDevices = true;
    await t.pumpWidget(app);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('report-chart')), findsOneWidget);
    expect(find.byKey(const Key('report-device')), findsNothing);
  });

  test('ApiClient.getDeviceUsage: gửi from/to đúng dạng, bỏ dòng hỏng', () async {
    final server = _Server();
    final session = ConnectionSession(store: InMemorySecureStore());
    await session.load();
    await session.setBaseUrl('https://api.test');
    await session.saveParentTokens(access: 'a', refresh: 'r');
    final api = ApiClient(session: session, client: MockClient(server.handle));
    final days = await api.getDeviceUsage(
      5,
      from: DateTime(2026, 1, 5),
      to: DateTime(2026, 10, 31),
    );
    expect(server.calls.single, 'GET /api/devices/5/usage?from=2026-01-05&to=2026-10-31');
    expect(days, hasLength(2)); // dòng "hỏng" bị bỏ
    expect(days.last.apps['com.google.android.youtube'], 80);
    expect(days.first.blocks, 2);
  });
}
