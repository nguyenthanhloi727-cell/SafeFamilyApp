import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:safe_family_app/core/network/api_client.dart';
import 'package:safe_family_app/core/network/api_scope.dart';
import 'package:safe_family_app/core/network/connection_session.dart';
import 'package:safe_family_app/core/network/remote_commands.dart';
import 'package:safe_family_app/core/theme/app_theme.dart';
import 'package:safe_family_app/features/app_lock/app_lock_config.dart';
import 'package:safe_family_app/features/app_lock/data/app_lock_store.dart';
import 'package:safe_family_app/features/app_lock/presentation/app_lock_controller.dart';
import 'package:safe_family_app/features/app_lock/presentation/app_lock_page.dart';
import 'package:safe_family_app/features/time_limit/presentation/pause_card.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../../helpers/app_lock_fakes.dart';
import '../../helpers/security_fakes.dart';

Future<ConnectionSession> _session({
  ConnectionMode mode = ConnectionMode.parent,
  int? child = 5,
}) async {
  final session = ConnectionSession(store: InMemorySecureStore());
  await session.load();
  await session.setBaseUrl('https://api.test');
  await session.setMode(mode);
  await session.saveParentTokens(access: 'a', refresh: 'r');
  await session.selectChild(child);
  return session;
}

Widget _wrap(ConnectionSession session, List<http.Request> sent, Widget page) {
  final client = MockClient((r) async {
    sent.add(r);
    return http.Response(
      jsonEncode({
        'id': 1,
        'type': 'x',
        'payloadJson': '{}',
        'createdAt': '2026-01-01T00:00:00Z',
      }),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
  return ConnectionScope(
    session: session,
    child: ApiScope(
      client: ApiClient(session: session, client: client),
      child: MaterialApp(theme: AppTheme.light, home: page),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('payload lệnh', () {
    expect(jsonDecode(RemoteCommands.unlockTempPayload('a.b', 15)), {
      'package': 'a.b',
      'minutes': 15,
    });
    expect(jsonDecode(RemoteCommands.packagePayload('a.b')), {
      'package': 'a.b',
    });
  });

  testWidgets(
    'app_lock_page: mở tạm gửi lệnh cho máy con, không mở trên máy mẹ',
    (tester) async {
      final platform = FakeAppLockPlatform();
      final controller = AppLockController(
        platform: platform,
        store: AppLockStore(prefs: SharedPreferencesAsync()),
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      final sent = <http.Request>[];
      await tester.pumpWidget(
        AppLockScope(
          controller: controller,
          child: _wrap(await _session(), sent, const AppLockPage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chặn nhanh YouTube'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.timer_outlined));
      await tester.pumpAndSettle();

      final commands = sent.where(
        (r) => r.url.path == '/api/devices/5/commands',
      );
      expect(commands, hasLength(1));
      final body = jsonDecode(commands.single.body) as Map<String, dynamic>;
      expect(body['type'], 'app_unlock_temp');
      expect(jsonDecode(body['payloadJson'] as String), {
        'package': 'com.google.android.youtube',
        'minutes': tempUnlockMinutes,
      });
      expect(platform.blocked, {'com.google.android.youtube'});
      expect(platform.relocks, isEmpty);
    },
  );

  testWidgets(
    'app_lock_page: chưa chọn máy con thì mở tạm trên máy này như cũ',
    (tester) async {
      final platform = FakeAppLockPlatform();
      final controller = AppLockController(
        platform: platform,
        store: AppLockStore(prefs: SharedPreferencesAsync()),
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      final sent = <http.Request>[];
      await tester.pumpWidget(
        AppLockScope(
          controller: controller,
          child: _wrap(await _session(child: null), sent, const AppLockPage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chặn nhanh YouTube'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.timer_outlined));
      await tester.pumpAndSettle();

      expect(sent, isEmpty);
      expect(platform.blocked, isEmpty);
      expect(platform.relocks.keys, ['com.google.android.youtube']);
      controller.dispose();
    },
  );

  testWidgets('pause_card: chế độ mẹ gửi pause / unpause tới máy con', (
    tester,
  ) async {
    final sent = <http.Request>[];
    await tester.pumpWidget(
      _wrap(await _session(), sent, const Scaffold(body: PauseCard())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tạm dừng máy con'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('30 phút'));
    await tester.pumpAndSettle();
    var body = jsonDecode(sent.last.body) as Map<String, dynamic>;
    expect(body['type'], 'pause');
    expect(jsonDecode(body['payloadJson'] as String), {'minutes': 30});

    await tester.pumpAndSettle(const Duration(seconds: 5));
    await tester.tap(find.text('Tạm dừng máy con'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tiếp tục dùng máy (hết tạm dừng)'));
    await tester.pumpAndSettle();
    body = jsonDecode(sent.last.body) as Map<String, dynamic>;
    expect(body['type'], 'unpause');
    expect(sent, hasLength(2));
  });
}
