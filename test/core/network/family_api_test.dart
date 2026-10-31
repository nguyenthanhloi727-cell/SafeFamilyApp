import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:safe_family_app/core/network/api_client.dart';
import 'package:safe_family_app/core/network/connection_session.dart';

import '../../helpers/security_fakes.dart';

http.Response _json(Object? body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

Future<(ConnectionSession, ApiClient, List<String>, Map<String, Object?>)> _api(
  Future<http.Response> Function(http.Request) respond,
) async {
  final calls = <String>[];
  final bodies = <String, Object?>{};
  final session = ConnectionSession(store: InMemorySecureStore());
  await session.load();
  await session.setBaseUrl('https://api.test');
  await session.saveParentTokens(access: 'a', refresh: 'r1', email: 'me@x.vn');
  await session.setMode(ConnectionMode.parent);
  final api = ApiClient(
    session: session,
    client: MockClient((r) {
      final key = '${r.method} ${r.url.path}';
      calls.add(key);
      if (r.body.isNotEmpty) bodies[key] = jsonDecode(r.body);
      return respond(r);
    }),
    retryDelay: Duration.zero,
  );
  return (session, api, calls, bodies);
}

void main() {
  group('người giám hộ thứ 2 (API-02)', () {
    test('family đọc danh sách người giám hộ', () async {
      final (_, api, _, _) = await _api(
        (_) async => _json({
          'id': 1,
          'name': 'Nhà',
          'isOwner': false,
          'members': [
            {'id': 1, 'email': 'me@x.vn', 'isOwner': true, 'isMe': false},
            {'id': 2, 'email': 'bo@x.vn', 'isOwner': false, 'isMe': true},
          ],
        }),
      );
      final f = await api.family();
      expect(f.name, 'Nhà');
      expect(f.isOwner, isFalse);
      expect(f.members.map((m) => m.email), ['me@x.vn', 'bo@x.vn']);
      expect(f.members.last.isMe, isTrue);
    });

    test('inviteGuardian trả mã 8 số và hạn', () async {
      final (_, api, calls, _) = await _api(
        (_) async => _json({
          'code': '12345678',
          'expiresAt': '2026-10-31T10:30:00Z',
        }),
      );
      final c = await api.inviteGuardian();
      expect(c.code, '12345678');
      expect(calls, ['POST /api/family/invite']);
    });

    test('inviteGuardian người không phải chủ → 403', () async {
      final (_, api, _, _) = await _api(
        (_) async => _json({'error': 'Chỉ chủ gia đình'}, 403),
      );
      await expectLater(
        api.inviteGuardian(),
        throwsA(isA<ApiException>().having((e) => e.isForbidden, 'isForbidden', true)),
      );
    });

    test('joinFamily gửi mã + email + mật khẩu và lưu token mới', () async {
      final (session, api, _, bodies) = await _api(
        (_) async => _json({
          'accessToken': 'a2',
          'refreshToken': 'r2',
          'familyId': 7,
        }),
      );
      final r = await api.joinFamily('12345678', 'bo@x.vn', 'password123');
      expect(bodies['POST /api/family/join'], {
        'code': '12345678',
        'email': 'bo@x.vn',
        'password': 'password123',
      });
      expect(r.familyId, 7);
      expect(session.refreshToken, 'r2');
    });

    test('joinFamily mã sai → 400, giữ phiên cũ', () async {
      final (session, api, _, _) = await _api(
        (_) async => _json({'error': 'Mã mời sai hoặc đã hết hạn.'}, 400),
      );
      await expectLater(
        api.joinFamily('00000000', 'bo@x.vn', 'password123'),
        throwsA(isA<ApiException>()),
      );
      expect(session.refreshToken, 'r1');
    });

    test('removeGuardian gọi đúng đường dẫn', () async {
      final (_, api, calls, _) = await _api((_) async => http.Response('', 204));
      await api.removeGuardian(5);
      expect(calls, ['DELETE /api/family/members/5']);
    });

    test('leaveFamily xóa phiên cục bộ sau khi server đồng ý', () async {
      final (session, api, calls, _) = await _api((_) async => http.Response('', 204));
      await api.leaveFamily();
      expect(calls, ['POST /api/family/leave']);
      expect(session.refreshToken, isNull);
    });
  });
}
