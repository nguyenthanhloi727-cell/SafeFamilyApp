import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:safe_family_app/core/network/api_client.dart';
import 'package:safe_family_app/core/network/connection_session.dart';

import '../../helpers/security_fakes.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

Future<ConnectionSession> _session() async {
  final s = ConnectionSession(store: InMemorySecureStore());
  await s.load();
  await s.setBaseUrl('https://api.test');
  return s;
}

void main() {
  test('normalizeBaseUrl bỏ dấu / cuối và thêm https', () {
    expect(
      ConnectionSession.normalizeBaseUrl(' api.test/ '),
      'https://api.test',
    );
    expect(
      ConnectionSession.normalizeBaseUrl('http://10.0.2.2:5025//'),
      'http://10.0.2.2:5025',
    );
  });

  test('login lưu token vào phiên', () async {
    final session = await _session();
    final api = ApiClient(
      session: session,
      client: MockClient((req) async {
        expect(req.url.toString(), 'https://api.test/api/auth/login');
        return _json({
          'accessToken': 'a1',
          'refreshToken': 'r1',
          'familyId': 7,
        });
      }),
    );
    await api.login('me@x.vn', 'matkhau123');
    expect(session.accessToken, 'a1');
    expect(session.isParentLoggedIn, isTrue);
    expect(session.email, 'me@x.vn');
  });

  test('401 thì tự làm mới access token rồi gọi lại', () async {
    final session = await _session();
    await session.saveParentTokens(access: 'old', refresh: 'r1');
    final seen = <String>[];
    final api = ApiClient(
      session: session,
      client: MockClient((req) async {
        seen.add('${req.url.path} ${req.headers['Authorization']}');
        if (req.url.path == '/api/auth/refresh') {
          return _json({
            'accessToken': 'new',
            'refreshToken': 'r2',
            'familyId': 1,
          });
        }
        if (req.headers['Authorization'] == 'Bearer old') {
          return http.Response('', 401);
        }
        return _json([
          {'id': 3, 'name': 'Bi', 'lastSeenAt': null},
        ]);
      }),
    );
    final devices = await api.listDevices();
    expect(devices.single.name, 'Bi');
    expect(session.refreshToken, 'r2');
    expect(seen, [
      '/api/devices Bearer old',
      '/api/auth/refresh null',
      '/api/devices Bearer new',
    ]);
  });

  test('claim lưu token thiết bị; mã sai trả thông báo của server', () async {
    final session = await _session();
    final api = ApiClient(
      session: session,
      client: MockClient((req) async {
        final code = (jsonDecode(req.body) as Map)['code'];
        return code == '123456'
            ? _json({'deviceToken': 'dt', 'deviceId': 9, 'deviceName': 'Bi'})
            : _json({'error': 'Mã sai hoặc đã hết hạn.'}, 400);
      }),
    );
    await expectLater(
      api.claimPairingCode('000000'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          'Mã sai hoặc đã hết hạn.',
        ),
      ),
    );
    expect(session.isChildPaired, isFalse);
    await api.claimPairingCode('123456');
    expect(session.deviceToken, 'dt');
    expect(session.deviceId, 9);
  });

  test('GET thử lại khi mất mạng, POST thì không', () async {
    final session = await _session();
    var gets = 0;
    var posts = 0;
    final api = ApiClient(
      session: session,
      retryDelay: Duration.zero,
      client: MockClient((req) async {
        if (req.method == 'GET') {
          gets++;
          if (gets < 3) throw http.ClientException('mất mạng');
          return _json({'version': 2, 'json': '{}'});
        }
        posts++;
        throw http.ClientException('mất mạng');
      }),
    );
    await session.saveDevice(token: 'dt', id: 1);
    expect((await api.fetchMyPolicy()).version, 2);
    expect(gets, 3);
    await expectLater(
      api.ackCommand(1),
      throwsA(
        isA<ApiException>().having((e) => e.isNetwork, 'isNetwork', isTrue),
      ),
    );
    expect(posts, 1);
  });

  test('409 khi lệch phiên bản luật', () async {
    final session = await _session();
    await session.saveParentTokens(access: 'a', refresh: 'r');
    final api = ApiClient(
      session: session,
      client: MockClient((_) async => _json({'error': 'x'}, 409)),
    );
    await expectLater(
      api.putPolicy(1, '{}', 0),
      throwsA(
        isA<ApiException>().having((e) => e.isConflict, 'isConflict', isTrue),
      ),
    );
  });
}
