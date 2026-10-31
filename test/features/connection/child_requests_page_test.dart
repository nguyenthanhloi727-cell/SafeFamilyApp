import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:safe_family_app/core/network/api_client.dart';
import 'package:safe_family_app/core/network/api_scope.dart';
import 'package:safe_family_app/core/network/child_status_text.dart';
import 'package:safe_family_app/core/network/connection_session.dart';
import 'package:safe_family_app/core/security/biometric_authenticator.dart';
import 'package:safe_family_app/core/security/parent_guard.dart';
import 'package:safe_family_app/features/connection/presentation/child_requests_page.dart';

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
  final bodies = <String, Object?>{};
  int decideStatus = 200;
  bool extraPending = true;

  Future<http.Response> handle(http.Request r) async {
    final key = '${r.method} ${r.url.path}';
    calls.add(key);
    if (r.body.isNotEmpty) bodies[key] = jsonDecode(r.body);
    if (key == 'GET /api/devices/5/requests') {
      return _json([
        {
          'id': 12,
          'deviceId': 5,
          'kind': 'extra_time',
          'payload': '{"minutes":30}',
          'status': extraPending ? 'pending' : 'approved',
          'createdAt': _utcAgo(const Duration(minutes: 4)),
          'decidedAt': extraPending ? null : _utcAgo(const Duration(minutes: 1)),
        },
        {
          'id': 11,
          'deviceId': 5,
          'kind': 'study_done',
          'payload': '{}',
          'status': 'pending',
          'createdAt': _utcAgo(const Duration(minutes: 9)),
          'decidedAt': null,
        },
        {
          'id': 10,
          'deviceId': 5,
          'kind': 'extra_time',
          'payload': '{"minutes":15}',
          'status': 'rejected',
          'createdAt': _utcAgo(const Duration(hours: 3)),
          'decidedAt': _utcAgo(const Duration(hours: 2)),
        },
      ]);
    }
    if (key.startsWith('PUT /api/requests/')) {
      return decideStatus == 200
          ? _json({'id': 12})
          : _json({'error': 'Yêu cầu đã được quyết định.'}, decideStatus);
    }
    return _json({'error': 'không có route $key'}, 404);
  }
}

Future<(_Server, Widget)> _page(ParentGuard? guard) async {
  final server = _Server();
  final session = ConnectionSession(store: InMemorySecureStore());
  await session.load();
  await session.setBaseUrl('https://api.test');
  await session.saveParentTokens(access: 'a', refresh: 'r');
  final api = ApiClient(session: session, client: MockClient(server.handle));
  Widget app = ApiScope(
    client: api,
    child: MaterialApp(
      home: ChildRequestsPage(device: DeviceInfo(5, 'Bé Bin', null)),
    ),
  );
  if (guard != null) app = ParentGuardScope(guard: guard, child: app);
  return (server, app);
}

void main() {
  test('nhãn yêu cầu và lệnh cộng giờ cho mẹ đọc', () {
    final r = ChildRequestInfo(
      id: 1,
      deviceId: 5,
      kind: RequestKind.extraTime,
      minutes: 15,
      status: 'pending',
      createdAt: DateTime.now(),
    );
    expect(requestLabel(r), 'Con xin thêm 15 phút');
    expect(r.approveMinutes, 15);
    final big = ChildRequestInfo(
      id: 2,
      deviceId: 5,
      kind: RequestKind.extraTime,
      minutes: 240,
      status: 'pending',
      createdAt: DateTime.now(),
    );
    expect(big.approveMinutes, ChildRequestInfo.maxApproveMinutes);
    expect(
      commandLabel(
        CommandInfo(
          id: 1,
          type: 'extra_time_grant',
          payloadJson: '{"minutes":20}',
          createdAt: DateTime.now(),
        ),
      ),
      'Cộng 20 phút giờ dùng máy hôm nay',
    );
  });

  testWidgets('hiện việc đang chờ và đã xử lý, chỉ có loại + số phút', (t) async {
    final (_, app) = await _page(null);
    await t.pumpWidget(app);
    await t.pumpAndSettle();

    expect(find.text('Con xin thêm 30 phút'), findsOneWidget);
    expect(find.text('Con báo đã học xong'), findsOneWidget);
    expect(find.byKey(const Key('approve-12')), findsOneWidget);
    expect(find.text('Duyệt 30 phút'), findsOneWidget);
    expect(find.byKey(const Key('done-10')), findsOneWidget);
    expect(find.textContaining('Đã từ chối'), findsOneWidget);
  });

  testWidgets('duyệt xin giờ gửi PUT approved kèm số phút, sau khi qua sinh trắc', (t) async {
    final bio = FakeBiometrics();
    final guard = await configuredGuard(
      biometrics: bio,
      biometricEnabled: true,
    );
    final (server, app) = await _page(guard);
    await t.pumpWidget(app);
    await t.pumpAndSettle();

    server.extraPending = false; // lần tải lại sau khi duyệt
    await t.tap(find.byKey(const Key('approve-12')));
    await t.pumpAndSettle();

    expect(bio.calls, 1, reason: 'duyệt phải hỏi khóa phụ huynh');
    expect(server.bodies['PUT /api/requests/12'], {
      'decision': 'approved',
      'minutes': 30,
    });
    expect(find.byKey(const Key('approve-12')), findsNothing);
    expect(find.byKey(const Key('done-12')), findsOneWidget);
  });

  testWidgets('từ chối cũng phải qua khóa; học tiếp không gửi minutes', (t) async {
    final bio = FakeBiometrics();
    final guard = await configuredGuard(
      biometrics: bio,
      biometricEnabled: true,
    );
    final (server, app) = await _page(guard);
    await t.pumpWidget(app);
    await t.pumpAndSettle();

    await t.tap(find.byKey(const Key('reject-11')));
    await t.pumpAndSettle();

    expect(bio.calls, 1);
    expect(server.bodies['PUT /api/requests/11'], {'decision': 'rejected'});
  });

  testWidgets('không qua khóa phụ huynh thì KHÔNG gọi server', (t) async {
    // Sinh trắc thất bại + hủy hộp PIN.
    final bio = FakeBiometrics(fallback: BiometricResult.canceled);
    final guard = await configuredGuard(
      biometrics: bio,
      biometricEnabled: true,
    );
    final (server, app) = await _page(guard);
    await t.pumpWidget(app);
    await t.pumpAndSettle();

    await t.tap(find.byKey(const Key('approve-12')));
    await t.pumpAndSettle();
    if (find.byTooltip('Hủy').evaluate().isNotEmpty) {
      await t.tap(find.byTooltip('Hủy'));
      await t.pumpAndSettle();
    }

    expect(server.calls.where((c) => c.startsWith('PUT ')), isEmpty);
    expect(find.byKey(const Key('approve-12')), findsOneWidget);
  });

  testWidgets('409 đã xử lý ở nơi khác: báo lỗi và tải lại', (t) async {
    final (server, app) = await _page(null);
    await t.pumpWidget(app);
    await t.pumpAndSettle();

    server.decideStatus = 409;
    await t.tap(find.byKey(const Key('approve-12')));
    await t.pumpAndSettle();

    expect(find.text('Yêu cầu đã được quyết định.'), findsOneWidget);
    expect(
      server.calls.where((c) => c == 'GET /api/devices/5/requests'),
      hasLength(2),
    );
  });
}
