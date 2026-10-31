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
import 'package:safe_family_app/features/connection/presentation/account_pages.dart';
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

/// Server giả: ghi lại lệnh gọi; [offline] = mất mạng; [status] ghi đè mã trả về cho mọi route /api/auth.
class _Server {
  _Server({this.offline = false, this.status = 204});

  bool offline;
  int status;
  final calls = <String>[];
  final bodies = <String, Object?>{};

  Future<http.Response> handle(http.Request r) async {
    final key = '${r.method} ${r.url.path}';
    calls.add(key);
    if (r.body.isNotEmpty) bodies[key] = jsonDecode(r.body);
    if (offline && r.url.path.startsWith('/api/auth/')) {
      throw http.ClientException('offline');
    }
    if (key == 'GET /api/devices') return _json([]);
    if (r.url.path.startsWith('/api/auth/')) {
      return status == 204
          ? http.Response('', 204)
          : _json({'error': 'Mật khẩu hiện tại không đúng.'}, status);
    }
    return _json({'error': 'không có route $key'}, 404);
  }
}

Future<(ConnectionSession, ApiClient, _Server)> _api({
  bool offline = false,
  int status = 204,
}) async {
  final server = _Server(offline: offline, status: status);
  final session = ConnectionSession(store: InMemorySecureStore());
  await session.load();
  await session.setBaseUrl('https://api.test');
  await session.saveParentTokens(access: 'a', refresh: 'r1', email: 'me@x.vn');
  await session.setMode(ConnectionMode.parent);
  final api = ApiClient(
    session: session,
    client: MockClient(server.handle),
    retryDelay: Duration.zero,
  );
  return (session, api, server);
}

Widget _app(ConnectionSession s, ApiClient api, ParentGuard? guard) {
  Widget app = ConnectionScope(
    session: s,
    child: ApiScope(
      client: api,
      child: MaterialApp(home: ConnectionPage(family: _Platform())),
    ),
  );
  if (guard != null) app = ParentGuardScope(guard: guard, child: app);
  return app;
}

void main() {
  group('ApiClient', () {
    test('logout gửi refresh token rồi xóa phiên cục bộ', () async {
      final (session, api, server) = await _api();
      expect(await api.logout(), isTrue);
      expect(server.bodies['POST /api/auth/logout'], {'refreshToken': 'r1'});
      expect(session.refreshToken, isNull);
      expect(session.mode, ConnectionMode.unset);
    });

    test('logout mất mạng: vẫn xóa phiên cục bộ nhưng trả false', () async {
      final (session, api, _) = await _api(offline: true);
      expect(await api.logout(), isFalse);
      expect(session.refreshToken, isNull);
      expect(session.accessToken, isNull);
    });

    test('changePassword gửi mật khẩu cũ/mới + refresh token phiên này', () async {
      final (session, api, server) = await _api();
      await api.changePassword('cu12345678', 'moi12345678');
      expect(server.bodies['POST /api/auth/change-password'], {
        'currentPassword': 'cu12345678',
        'newPassword': 'moi12345678',
        'refreshToken': 'r1',
      });
      expect(session.refreshToken, 'r1', reason: 'đổi mật khẩu không đăng xuất phiên này');
    });

    test('changePassword sai mật khẩu cũ → 403 và KHÔNG làm mới token', () async {
      final (_, api, server) = await _api(status: 403);
      await expectLater(
        api.changePassword('sai', 'moi12345678'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.isForbidden, '403', isTrue)
              .having((e) => e.message, 'message', 'Mật khẩu hiện tại không đúng.'),
        ),
      );
      expect(server.calls.where((c) => c.contains('refresh')), isEmpty);
    });

    test('deleteAccount gửi mật khẩu + confirm:true rồi xóa phiên', () async {
      final (session, api, server) = await _api();
      await api.deleteAccount('matkhau123');
      expect(server.bodies['DELETE /api/auth/account'], {
        'password': 'matkhau123',
        'confirm': true,
      });
      expect(session.refreshToken, isNull);
    });

    test('deleteAccount sai mật khẩu → 403 và giữ phiên', () async {
      final (session, api, _) = await _api(status: 403);
      await expectLater(api.deleteAccount('sai'), throwsA(isA<ApiException>()));
      expect(session.refreshToken, 'r1');
    });

    test('forgotPassword / resetPassword gửi đúng trường', () async {
      final (_, api, server) = await _api();
      await api.forgotPassword('me@x.vn');
      await api.resetPassword('me@x.vn', '123456', 'moi12345678');
      expect(server.bodies['POST /api/auth/forgot-password'], {'email': 'me@x.vn'});
      expect(server.bodies['POST /api/auth/reset-password'], {
        'email': 'me@x.vn',
        'code': '123456',
        'newPassword': 'moi12345678',
      });
    });
  });

  group('màn hình', () {
    testWidgets('Đăng xuất máy mẹ qua khóa phụ huynh thì gọi logout thật', (t) async {
      final bio = FakeBiometrics();
      final guard = await configuredGuard(biometrics: bio, biometricEnabled: true);
      final (session, api, server) = await _api();
      await t.pumpWidget(_app(session, api, guard));
      await t.pumpAndSettle();

      await t.tap(find.byKey(const Key('disconnect')));
      await t.pumpAndSettle();

      expect(bio.calls, 1, reason: 'đăng xuất phải hỏi khóa phụ huynh');
      expect(server.bodies['POST /api/auth/logout'], {'refreshToken': 'r1'});
      expect(session.refreshToken, isNull);
    });

    testWidgets('không qua khóa phụ huynh thì KHÔNG đăng xuất', (t) async {
      final bio = FakeBiometrics(fallback: BiometricResult.canceled);
      final guard = await configuredGuard(biometrics: bio, biometricEnabled: true);
      final (session, api, server) = await _api();
      await t.pumpWidget(_app(session, api, guard));
      await t.pumpAndSettle();

      await t.tap(find.byKey(const Key('disconnect')));
      await t.pumpAndSettle();
      if (find.byTooltip('Hủy').evaluate().isNotEmpty) {
        await t.tap(find.byTooltip('Hủy'));
        await t.pumpAndSettle();
      }

      expect(server.calls.where((c) => c.contains('logout')), isEmpty);
      expect(session.refreshToken, 'r1');
    });

    testWidgets('xóa tài khoản: khóa phụ huynh, nhập mật khẩu, mới gọi DELETE', (t) async {
      final bio = FakeBiometrics();
      final guard = await configuredGuard(biometrics: bio, biometricEnabled: true);
      final (session, api, server) = await _api();
      await t.pumpWidget(_app(session, api, guard));
      await t.pumpAndSettle();

      await t.ensureVisible(find.byKey(const Key('delete-account')));
      await t.tap(find.byKey(const Key('delete-account')));
      await t.pumpAndSettle();
      expect(bio.calls, 1, reason: 'xóa tài khoản phải hỏi khóa phụ huynh');
      expect(
        tester(find.byKey(const Key('delete-confirm'))).onPressed,
        isNull,
        reason: 'chưa nhập mật khẩu thì chưa xóa được',
      );
      expect(server.calls.where((c) => c.startsWith('DELETE ')), isEmpty);

      await t.enterText(find.byKey(const Key('delete-password')), 'matkhau123');
      await t.pump();
      await t.tap(find.byKey(const Key('delete-confirm')));
      await t.pumpAndSettle();

      expect(server.bodies['DELETE /api/auth/account'], {
        'password': 'matkhau123',
        'confirm': true,
      });
      expect(session.refreshToken, isNull);
    });

    testWidgets('xóa tài khoản sai mật khẩu: hiện lỗi, không xóa phiên', (t) async {
      final (session, api, server) = await _api(status: 403);
      server.status = 403;
      await t.pumpWidget(_app(session, api, null));
      await t.pumpAndSettle();

      await t.ensureVisible(find.byKey(const Key('delete-account')));
      await t.tap(find.byKey(const Key('delete-account')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('delete-password')), 'sai');
      await t.pump();
      await t.tap(find.byKey(const Key('delete-confirm')));
      await t.pumpAndSettle();

      expect(find.text('Mật khẩu hiện tại không đúng.'), findsOneWidget);
      expect(session.refreshToken, 'r1');
    });

    testWidgets('đổi mật khẩu: kiểm tra phía máy rồi mới gọi API', (t) async {
      final (session, api, server) = await _api();
      await t.pumpWidget(
        ConnectionScope(
          session: session,
          child: ApiScope(
            client: api,
            child: const MaterialApp(home: ChangePasswordPage()),
          ),
        ),
      );
      Future<void> submit(String cur, String next, String again) async {
        await t.enterText(find.byKey(const Key('current-password')), cur);
        await t.enterText(find.byKey(const Key('new-password')), next);
        await t.enterText(find.byKey(const Key('new-password-again')), again);
        await t.tap(find.byKey(const Key('change-password-submit')));
        await t.pumpAndSettle();
      }

      await submit('cu12345678', 'ngan', 'ngan');
      expect(find.text('Mật khẩu mới phải từ 8 ký tự.'), findsOneWidget);
      await submit('cu12345678', 'cu12345678', 'cu12345678');
      expect(find.text('Mật khẩu mới phải khác mật khẩu hiện tại.'), findsOneWidget);
      await submit('cu12345678', 'moi12345678', 'khac12345678');
      expect(find.text('Hai lần nhập mật khẩu mới chưa giống nhau.'), findsOneWidget);
      expect(server.calls.where((c) => c.contains('change-password')), isEmpty);

      await submit('cu12345678', 'moi12345678', 'moi12345678');
      expect(server.bodies['POST /api/auth/change-password'], {
        'currentPassword': 'cu12345678',
        'newPassword': 'moi12345678',
        'refreshToken': 'r1',
      });
    });

    testWidgets('quên mật khẩu: xin mã rồi đặt mật khẩu mới', (t) async {
      final (session, api, server) = await _api();
      await t.pumpWidget(
        ConnectionScope(
          session: session,
          child: ApiScope(
            client: api,
            child: const MaterialApp(
              home: ForgotPasswordPage(initialEmail: 'me@x.vn'),
            ),
          ),
        ),
      );
      await t.tap(find.byKey(const Key('forgot-send')));
      await t.pumpAndSettle();
      expect(server.bodies['POST /api/auth/forgot-password'], {'email': 'me@x.vn'});

      await t.enterText(find.byKey(const Key('forgot-code')), '12345');
      await t.enterText(find.byKey(const Key('forgot-new-password')), 'moi12345678');
      await t.tap(find.byKey(const Key('forgot-reset')));
      await t.pumpAndSettle();
      expect(find.text('Mã gồm đúng 6 chữ số.'), findsOneWidget);
      expect(server.calls.where((c) => c.contains('reset-password')), isEmpty);

      await t.enterText(find.byKey(const Key('forgot-code')), '123456');
      await t.tap(find.byKey(const Key('forgot-reset')));
      await t.pumpAndSettle();
      expect(server.bodies['POST /api/auth/reset-password'], {
        'email': 'me@x.vn',
        'code': '123456',
        'newPassword': 'moi12345678',
      });
    });
  });
}

FilledButton tester(Finder f) =>
    (f.evaluate().single.widget as FilledButton);
