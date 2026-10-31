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
import 'package:safe_family_app/features/connection/data/family_platform.dart';
import 'package:safe_family_app/features/connection/presentation/connection_page.dart';

import '../../helpers/security_fakes.dart';

http.Response _json(Object? body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

class _Platform implements FamilyPlatform {
  @override
  Future<void> configure(String baseUrl, String token) async {}
  @override
  Future<void> clear() async {}
  @override
  Future<bool> syncNow() async => true;
  @override
  Future<LocationPermissionStatus> locationStatus() async =>
      const LocationPermissionStatus(foreground: true, background: true);
  @override
  Future<void> requestLocation() async {}
  @override
  Future<bool> requestBackgroundLocation() async => true;
}

class _Server {
  String name = 'Con';
  final calls = <String>[];
  final bodies = <String, Object?>{};

  Future<http.Response> handle(http.Request r) async {
    final key = '${r.method} ${r.url.path}';
    calls.add(key);
    if (r.body.isNotEmpty) bodies[key] = jsonDecode(r.body);
    switch (key) {
      case 'GET /api/devices':
        return _json([
          {'id': 5, 'name': name, 'pairedAt': '2026-10-31T01:00:00', 'lastSeenAt': null},
        ]);
      case 'PATCH /api/devices/5':
        name = (bodies[key] as Map<String, dynamic>)['name'] as String;
        name = name.trim();
        return _json({'id': 5, 'name': name, 'pairedAt': '2026-10-31T01:00:00', 'lastSeenAt': null});
      case 'GET /api/devices/me':
        return _json({
          'id': 5,
          'name': 'Bé Bin',
          'familyName': 'Nhà Bin',
          'pairedAt': '2026-10-31T01:00:00',
          'policyVersion': 3,
        });
    }
    return _json({'error': 'không có route $key'}, 404);
  }
}

Future<(_Server, Widget)> _app(ConnectionMode mode, ParentGuard? guard) async {
  final server = _Server();
  final session = ConnectionSession(store: InMemorySecureStore());
  await session.load();
  await session.setBaseUrl('https://api.test');
  await session.saveParentTokens(access: 'a', refresh: 'r');
  await session.saveDevice(token: 'd', id: 5);
  await session.setMode(mode);
  final api = ApiClient(session: session, client: MockClient(server.handle));
  Widget app = ConnectionScope(
    session: session,
    child: ApiScope(
      client: api,
      child: MaterialApp(home: ConnectionPage(family: _Platform())),
    ),
  );
  if (guard != null) app = ParentGuardScope(guard: guard, child: app);
  return (server, app);
}

void main() {
  testWidgets('mẹ đổi tên qua khóa phụ huynh thì danh sách đổi theo', (t) async {
    final bio = FakeBiometrics();
    final guard = await configuredGuard(biometrics: bio, biometricEnabled: true);
    final (server, app) = await _app(ConnectionMode.parent, guard);
    await t.pumpWidget(app);
    await t.pumpAndSettle();
    expect(find.text('Con'), findsOneWidget);

    await t.tap(find.byKey(const Key('rename-5')));
    await t.pumpAndSettle();
    expect(bio.calls, 1, reason: 'đổi tên phải hỏi khóa phụ huynh');
    await t.enterText(find.byKey(const Key('rename-field')), '  Bé Bin ');
    await t.pump();
    await t.tap(find.byKey(const Key('rename-save')));
    await t.pumpAndSettle();

    expect(server.bodies['PATCH /api/devices/5'], {'name': 'Bé Bin'});
    expect(find.text('Bé Bin'), findsOneWidget);
    expect(find.text('Con'), findsNothing);
  });

  testWidgets('không qua khóa phụ huynh thì KHÔNG gọi PATCH', (t) async {
    final bio = FakeBiometrics(fallback: BiometricResult.canceled);
    final guard = await configuredGuard(biometrics: bio, biometricEnabled: true);
    final (server, app) = await _app(ConnectionMode.parent, guard);
    await t.pumpWidget(app);
    await t.pumpAndSettle();

    await t.tap(find.byKey(const Key('rename-5')));
    await t.pumpAndSettle();
    if (find.byTooltip('Hủy').evaluate().isNotEmpty) {
      await t.tap(find.byTooltip('Hủy'));
      await t.pumpAndSettle();
    }

    expect(server.calls.where((c) => c.startsWith('PATCH ')), isEmpty);
    expect(find.byKey(const Key('rename-field')), findsNothing);
  });

  testWidgets('máy con hiện "đang được giám sát bởi" tên gia đình', (t) async {
    final (_, app) = await _app(ConnectionMode.child, null);
    await t.pumpWidget(app);
    await t.pumpAndSettle();

    expect(find.text('Bé Bin đang được giám sát bởi Nhà Bin'), findsOneWidget);
  });
}
