import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:safe_family_app/app/app.dart';
import 'package:safe_family_app/core/network/api_client.dart';
import 'package:safe_family_app/core/network/connection_session.dart';
import 'package:safe_family_app/core/settings/setup_settings.dart';
import 'package:safe_family_app/features/connection/presentation/role_page.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../helpers/security_fakes.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('hết phiên: hiện thông báo, bấm OK thì về màn chọn máy mẹ/con', (
    tester,
  ) async {
    final guard = await configuredGuard();
    final setup = SetupSettings();
    await setup.load();
    await setup.markDone();
    final connection = ConnectionSession(store: InMemorySecureStore());
    await connection.load();
    await connection.setMode(ConnectionMode.parent);
    await connection.saveParentTokens(access: 'old', refresh: 'dead');
    final api = ApiClient(
      session: connection,
      client: MockClient((_) async => http.Response('', 401)),
    );
    await tester.pumpWidget(
      SafeFamilyApp(
        guard: guard,
        setup: setup,
        connection: connection,
        api: api,
      ),
    );
    await tester.pump();

    // Một lệnh gọi API bất kỳ của mẹ gặp 401 và không làm mới được token.
    await expectLater(api.listDevices(), throwsA(isA<ApiException>()));
    await tester.pump();

    expect(find.text('Phiên đã hết hạn'), findsOneWidget);
    await tester.tap(find.byKey(const Key('session-expired-ok')));
    await tester.pumpAndSettle();

    expect(find.text('Phiên đã hết hạn'), findsNothing);
    expect(find.byType(RolePage), findsOneWidget);
    expect(connection.isChosen, isFalse);
    expect(connection.refreshToken, isNull);
  });
}
