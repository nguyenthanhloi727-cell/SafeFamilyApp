import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:safe_family_app/core/network/api_client.dart';
import 'package:safe_family_app/core/network/api_scope.dart';
import 'package:safe_family_app/core/network/connection_session.dart';
import 'package:safe_family_app/core/security/biometric_authenticator.dart';
import 'package:safe_family_app/core/security/parent_guard.dart';
import 'package:safe_family_app/core/theme/app_theme.dart';
import 'package:safe_family_app/features/new_app/data/new_app_platform.dart';
import 'package:safe_family_app/features/new_app/presentation/new_apps_page.dart';

import '../../helpers/security_fakes.dart';

http.Response _json(Object? body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> _app(int id, String pkg, String label, String status) => {
  'id': id,
  'packageName': pkg,
  'label': label,
  'firstSeenAt': '2026-10-31T01:00:00',
  'status': status,
  'decidedAt': status == 'new' ? null : '2026-10-31T01:05:00',
};

class _Server {
  final calls = <String>[];
  final bodies = <String, Object?>{};
  int putStatus = 200;
  final apps = [
    _app(2, 'com.game.vui', 'Game vui', 'new'),
    _app(1, 'com.tiktok.x', 'TikTok', 'blocked'),
  ];

  Future<http.Response> handle(http.Request r) async {
    final key = '${r.method} ${r.url.path}';
    calls.add('$key${r.url.query.isEmpty ? '' : '?${r.url.query}'}');
    if (r.body.isNotEmpty) bodies[key] = jsonDecode(r.body);
    if (r.method == 'GET' && r.url.path == '/api/devices/5/apps') {
      final status = r.url.queryParameters['status'];
      return _json([
        for (final a in apps)
          if (status == null || a['status'] == status) a,
      ]);
    }
    if (r.method == 'PUT' && r.url.path.startsWith('/api/devices/5/apps/')) {
      if (putStatus != 200) {
        return _json({'error': 'Không tìm thấy.'}, putStatus);
      }
      final pkg = r.url.pathSegments.last;
      final status = (jsonDecode(r.body) as Map)['status'] as String;
      for (final a in apps) {
        if (a['packageName'] == pkg) a['status'] = status;
      }
      return _json({'id': 2});
    }
    return _json({'error': 'không có route $key'}, 404);
  }
}

class _LocalPlatform implements NewAppPlatform {
  @override
  dynamic noSuchMethod(Invocation i) =>
      throw StateError('không được đụng máy này');
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
      theme: AppTheme.light,
      home: NewAppsPage(
        platform: _LocalPlatform(),
        remoteDevice: DeviceInfo(5, 'Bé Bin', null),
      ),
    ),
  );
  if (guard != null) app = ParentGuardScope(guard: guard, child: app);
  return (server, app);
}

void main() {
  testWidgets(
    'đọc từ server: app chờ duyệt và app đã chặn, không đụng máy này',
    (t) async {
      final (server, app) = await _page(null);
      await t.pumpWidget(app);
      await t.pumpAndSettle();

      expect(find.text('Game vui'), findsOneWidget);
      expect(find.text('com.game.vui'), findsOneWidget);
      expect(find.text('Đang chờ duyệt (1)'), findsOneWidget);
      expect(find.text('Đã chặn (1)'), findsOneWidget);
      expect(find.byKey(const Key('block-com.game.vui')), findsOneWidget);
      // App đã chặn chỉ có "Cho phép", không có "Chặn".
      expect(find.byKey(const Key('block-com.tiktok.x')), findsNothing);
      expect(server.calls, contains('GET /api/devices/5/apps?status=new'));
      expect(server.calls, contains('GET /api/devices/5/apps?status=blocked'));
    },
  );

  testWidgets('Cho phép gửi PUT allowed sau khi qua sinh trắc, rồi tải lại', (
    t,
  ) async {
    final bio = FakeBiometrics();
    final guard = await configuredGuard(
      biometrics: bio,
      biometricEnabled: true,
    );
    final (server, app) = await _page(guard);
    await t.pumpWidget(app);
    await t.pumpAndSettle();

    await t.tap(find.byKey(const Key('allow-com.game.vui')));
    await t.pumpAndSettle();

    expect(bio.calls, 1, reason: 'cho phép phải hỏi khóa phụ huynh');
    expect(server.bodies['PUT /api/devices/5/apps/com.game.vui'], {
      'status': 'allowed',
    });
    expect(find.text('Không có app nào chờ duyệt'), findsOneWidget);
  });

  testWidgets('Chặn gửi PUT blocked, cũng qua khóa; app chuyển sang Đã chặn', (
    t,
  ) async {
    final bio = FakeBiometrics();
    final guard = await configuredGuard(
      biometrics: bio,
      biometricEnabled: true,
    );
    final (server, app) = await _page(guard);
    await t.pumpWidget(app);
    await t.pumpAndSettle();

    await t.tap(find.byKey(const Key('block-com.game.vui')));
    await t.pumpAndSettle();

    expect(bio.calls, 1);
    expect(server.bodies['PUT /api/devices/5/apps/com.game.vui'], {
      'status': 'blocked',
    });
    expect(find.text('Đã chặn (2)'), findsOneWidget);
  });

  testWidgets('không qua khóa phụ huynh thì KHÔNG gọi server', (t) async {
    final bio = FakeBiometrics(fallback: BiometricResult.canceled);
    final guard = await configuredGuard(
      biometrics: bio,
      biometricEnabled: true,
    );
    final (server, app) = await _page(guard);
    await t.pumpWidget(app);
    await t.pumpAndSettle();

    await t.tap(find.byKey(const Key('allow-com.game.vui')));
    await t.pumpAndSettle();
    if (find.byTooltip('Hủy').evaluate().isNotEmpty) {
      await t.tap(find.byTooltip('Hủy'));
      await t.pumpAndSettle();
    }

    expect(server.calls.where((c) => c.startsWith('PUT ')), isEmpty);
    expect(find.byKey(const Key('allow-com.game.vui')), findsOneWidget);
  });

  testWidgets('server từ chối (404): báo lỗi, không crash, tải lại', (t) async {
    final (server, app) = await _page(null);
    await t.pumpWidget(app);
    await t.pumpAndSettle();

    server.putStatus = 404;
    await t.tap(find.byKey(const Key('allow-com.game.vui')));
    await t.pumpAndSettle();

    expect(find.text('Không tìm thấy.'), findsOneWidget);
    expect(
      server.calls.where((c) => c == 'GET /api/devices/5/apps?status=new'),
      hasLength(2),
    );
  });

  test('tên gói được mã hóa trong đường dẫn PUT', () async {
    final server = _Server();
    final session = ConnectionSession(store: InMemorySecureStore());
    await session.load();
    await session.setBaseUrl('https://api.test');
    await session.saveParentTokens(access: 'a', refresh: 'r');
    final api = ApiClient(session: session, client: MockClient(server.handle));
    await api.setDeviceAppStatus(5, 'com.game.vui', allow: false);
    expect(server.calls.single, 'PUT /api/devices/5/apps/com.game.vui');
    expect(server.bodies.values.single, {'status': 'blocked'});
  });
}
