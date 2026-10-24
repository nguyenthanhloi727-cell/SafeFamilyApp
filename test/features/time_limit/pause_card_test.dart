import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safe_family_app/core/theme/app_theme.dart';
import 'package:safe_family_app/features/time_limit/data/time_limit_platform.dart';
import 'package:safe_family_app/features/time_limit/presentation/pause_card.dart';

class _Platform implements TimeLimitPlatform {
  int left = 0;

  @override
  Future<int> pauseMinutesLeft() async => left;

  @override
  Future<void> startPause(int minutes) async =>
      left = minutes == 0 ? pauseUntilOff : minutes;

  @override
  Future<void> stopPause() async => left = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) async {}
}

Widget _app(_Platform platform) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(body: PauseCard(platform: platform)),
);

void main() {
  testWidgets('tạm dừng 30 phút rồi tiếp tục', (tester) async {
    final platform = _Platform();
    await tester.pumpWidget(_app(platform));
    await tester.pumpAndSettle();
    expect(find.text('Tạm dừng máy'), findsOneWidget);

    await tester.tap(find.text('Tạm dừng máy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('30 phút'));
    await tester.pumpAndSettle();
    expect(platform.left, 30);
    expect(find.text('Tiếp tục dùng máy'), findsOneWidget);

    await tester.tap(find.text('Tiếp tục dùng máy'));
    await tester.pumpAndSettle();
    expect(platform.left, 0);
    expect(find.text('Tạm dừng máy'), findsOneWidget);
  });

  testWidgets('"Cho tới khi tắt" hiện đúng trạng thái', (tester) async {
    final platform = _Platform()..left = pauseUntilOff;
    await tester.pumpWidget(_app(platform));
    await tester.pumpAndSettle();
    expect(find.textContaining('cho tới khi phụ huynh tắt'), findsOneWidget);
  });
}
