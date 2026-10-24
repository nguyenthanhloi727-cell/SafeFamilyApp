import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safe_family_app/core/theme/app_theme.dart';
import 'package:safe_family_app/features/new_app/data/new_app_platform.dart';
import 'package:safe_family_app/features/new_app/presentation/new_apps_page.dart';

class _FakeNewApps implements NewAppPlatform {
  bool enabled = true;
  bool notifications = true;
  List<PendingApp> apps = [
    const PendingApp(packageName: 'com.example.game', label: 'Game vui'),
  ];
  final approved = <String>[];

  @override
  Future<bool> isEnabled() async => enabled;

  @override
  Future<void> setEnabled(bool value) async => enabled = value;

  @override
  Future<List<PendingApp>> pending() async => List.of(apps);

  @override
  Future<void> approve(String packageName) async {
    approved.add(packageName);
    apps.removeWhere((a) => a.packageName == packageName);
  }

  @override
  Future<bool> consumeReviewRequest() async => false;

  @override
  Future<bool> notificationsAllowed() async => notifications;

  @override
  Future<void> requestNotifications() async => notifications = true;
}

Widget _host(NewAppPlatform platform) => MaterialApp(
  theme: AppTheme.light,
  home: NewAppsPage(platform: platform),
);

void main() {
  testWidgets('hiện app chờ duyệt, bấm Cho phép thì app biến mất', (
    tester,
  ) async {
    final platform = _FakeNewApps();
    await tester.pumpWidget(_host(platform));
    await tester.pumpAndSettle();

    expect(find.text('Game vui'), findsOneWidget);
    await tester.tap(find.text('Cho phép'));
    await tester.pumpAndSettle();

    expect(platform.approved, ['com.example.game']);
    expect(find.text('Không có app nào chờ duyệt'), findsOneWidget);
  });

  testWidgets('tắt tính năng thì không liệt kê app', (tester) async {
    final platform = _FakeNewApps()..enabled = false;
    await tester.pumpWidget(_host(platform));
    await tester.pumpAndSettle();

    expect(find.text('Tính năng đang tắt.'), findsOneWidget);
    expect(find.text('Game vui'), findsNothing);
  });

  testWidgets('chưa cấp quyền thông báo thì có nút xin quyền', (tester) async {
    final platform = _FakeNewApps()..notifications = false;
    await tester.pumpWidget(_host(platform));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cho phép thông báo'));
    await tester.pumpAndSettle();

    expect(platform.notifications, isTrue);
    expect(find.text('Chưa có thông báo'), findsNothing);
  });
}
