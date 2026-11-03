import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safe_family_app/core/network/connection_session.dart';
import 'package:safe_family_app/core/theme/app_theme.dart';
import 'package:safe_family_app/features/app_lock/data/app_lock_store.dart';
import 'package:safe_family_app/features/app_lock/presentation/app_lock_controller.dart';
import 'package:safe_family_app/features/connection/data/family_platform.dart';
import 'package:safe_family_app/features/connection/presentation/child_home_page.dart';
import 'package:safe_family_app/features/time_limit/data/time_limit_platform.dart';
import 'package:safe_family_app/features/time_limit/domain/time_limit_config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../../helpers/app_lock_fakes.dart';
import '../../helpers/security_fakes.dart';

class _Platform implements TimeLimitPlatform {
  _Platform({this.pause = 0, this.limit, this.used = 0, this.study = false});

  final int pause;
  final int? limit;
  final int used;
  final bool study;

  @override
  Future<TimeLimitConfig> load() async => TimeLimitConfig(
    enabled: limit != null,
    total: List<int?>.filled(7, limit),
  );
  @override
  Future<UsageToday?> usageToday() async => UsageToday(totalMinutes: used);
  @override
  Future<int> bonusMinutes() async => 0;
  @override
  Future<int> pauseMinutesLeft() async => pause;
  @override
  Future<StudyStatus> studyStatus() async => StudyStatus(active: study);
  @override
  Future<Map<String, String>> appLabels(List<String> packages) async => {
    for (final p in packages)
      p: p == 'com.google.android.youtube' ? 'YouTube' : p,
  };

  @override
  dynamic noSuchMethod(Invocation invocation) async {}
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  Future<void> pump(
    WidgetTester tester,
    TimeLimitPlatform platform, {
    Set<String> blocked = const {},
    FamilyPlatform? family,
    ConnectionSession? session,
  }) async {
    // Màn chính dài hơn khung test mặc định; ListView lười nên nút cuối trang cần chỗ.
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = AppLockController(
      platform: FakeAppLockPlatform(blocked: {...blocked}),
      store: AppLockStore(prefs: SharedPreferencesAsync()),
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    await tester.pumpWidget(
      ConnectionScope(
        session: session ?? ConnectionSession(store: InMemorySecureStore()),
        child: AppLockScope(
          controller: controller,
          child: MaterialApp(
            theme: AppTheme.light,
            home: ChildHomePage(
              platform: platform,
              family: family ?? _Family(),
              refreshEvery: const Duration(days: 1),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('hiện app đang bị chặn và thời gian còn lại hôm nay', (t) async {
    await pump(
      t,
      _Platform(limit: 120, used: 45),
      blocked: {'com.google.android.youtube'},
    );
    expect(find.text('YouTube'), findsOneWidget);
    expect(find.text('Đang bị chặn'), findsOneWidget);
    expect(find.text('Hôm nay còn 1 giờ 15 phút'), findsOneWidget);
    expect(find.text('Đã dùng 45 phút / 2 giờ.'), findsOneWidget);
    expect(find.byKey(const Key('child-parent-area')), findsOneWidget);
  });

  testWidgets('chưa chặn gì: báo rõ; máy tạm dừng: hiện thẻ tạm dừng', (
    t,
  ) async {
    await pump(t, _Platform(pause: 20));
    expect(find.text('Hiện chưa có ứng dụng nào bị chặn.'), findsOneWidget);
    expect(find.text('Máy đang tạm dừng'), findsOneWidget);
    expect(find.text('Còn 20 phút.'), findsOneWidget);
  });

  testWidgets('nút Đồng bộ với máy mẹ gọi đồng bộ ngay và báo kết quả', (t) async {
    final family = _Family();
    await pump(t, _Platform(), family: family);

    await t.tap(find.byKey(const Key('child-sync')));
    await t.pumpAndSettle();
    expect(family.syncs, 1);
    expect(find.text('Đã đồng bộ với máy mẹ.'), findsOneWidget);

    family.result = false;
    await t.pump(const Duration(seconds: 5));
    await t.tap(find.byKey(const Key('child-sync')));
    await t.pumpAndSettle();
    expect(find.text('Chưa đồng bộ được. Kiểm tra mạng rồi thử lại.'), findsOneWidget);
  });

  testWidgets('hiện đồng bộ lần cuối khi vừa đồng bộ', (t) async {
    final family = _Family()
      ..lastSync = DateTime.now().subtract(const Duration(minutes: 3));
    await pump(t, _Platform(), family: family);
    expect(find.text('Đồng bộ lần cuối: 3 phút trước.'), findsOneWidget);
  });

  testWidgets('chưa từng đồng bộ: báo chưa kết nối được máy mẹ', (t) async {
    await pump(t, _Platform());
    expect(find.text('Chưa kết nối được máy mẹ.'), findsOneWidget);
  });

  testWidgets('đồng bộ quá lâu: báo chưa kết nối kèm mốc cuối', (t) async {
    final stale = _Family()
      ..lastSync = DateTime.now().subtract(const Duration(hours: 2));
    await pump(t, _Platform(), family: stale);
    expect(
      find.text('Chưa kết nối được máy mẹ. Đồng bộ lần cuối: 2 giờ trước.'),
      findsOneWidget,
    );
  });

  testWidgets('bấm Đồng bộ mà thất bại: báo mất kết nối dù mốc còn mới', (
    t,
  ) async {
    final family = _Family()
      ..lastSync = DateTime.now().subtract(const Duration(minutes: 1))
      ..result = false;
    await pump(t, _Platform(), family: family);
    expect(find.text('Đồng bộ lần cuối: 1 phút trước.'), findsOneWidget);

    await t.tap(find.byKey(const Key('child-sync')));
    await t.pumpAndSettle();
    expect(
      find.text('Chưa kết nối được máy mẹ. Đồng bộ lần cuối: 1 phút trước.'),
      findsOneWidget,
    );
  });

  testWidgets('có khối minh bạch: mẹ xem được gì', (t) async {
    await pump(t, _Platform());
    await t.scrollUntilVisible(
      find.byKey(const Key('child-transparency')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.textContaining('Mẹ không xem nội dung tin nhắn hay trình duyệt.'),
      findsOneWidget,
    );
  });

  testWidgets('Xin thêm giờ: chọn 15 phút, gửi và hiện chờ mẹ duyệt', (t) async {
    final family = _Family();
    await pump(t, _Platform(), family: family);
    expect(find.byKey(const Key('child-extra-time-status')), findsNothing);

    await t.tap(find.byKey(const Key('child-extra-time')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('extra-time-15')));
    await t.pumpAndSettle();

    expect(family.queued, ['extra_time:15']);
    expect(find.text('Đã gửi, chờ mẹ duyệt.'), findsOneWidget);
    final button = t.widget<FilledButton>(
      find.byKey(const Key('child-extra-time')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('hiện kết quả mẹ đã duyệt / từ chối', (t) async {
    final family = _Family()
      ..statuses['extra_time'] = 'approved'
      ..statuses['study_done'] = 'denied';
    await pump(t, _Platform(study: true), family: family);
    expect(find.text('Mẹ đã duyệt.'), findsOneWidget);
    expect(find.text('Mẹ từ chối.'), findsOneWidget);
  });

  testWidgets('ngoài giờ học không có nút Con học xong rồi', (t) async {
    await pump(t, _Platform());
    expect(find.byKey(const Key('child-study-done')), findsNothing);
  });

  testWidgets('Con học xong rồi chỉ hiện trong giờ học và gửi study_done', (
    t,
  ) async {
    final family = _Family();
    await pump(t, _Platform(study: true), family: family);
    await t.tap(find.byKey(const Key('child-study-done')));
    await t.pumpAndSettle();
    expect(family.queued, ['study_done:0']);
    expect(find.text('Đã gửi, chờ mẹ duyệt.'), findsOneWidget);
  });

  testWidgets('Dành cho phụ huynh mở menu; Ngắt kết nối xóa phiên máy con', (
    t,
  ) async {
    final session = ConnectionSession(store: InMemorySecureStore());
    await session.load();
    await session.setMode(ConnectionMode.child);
    await pump(t, _Platform(), session: session);

    await t.tap(find.byKey(const Key('child-parent-area')));
    await t.pumpAndSettle();
    expect(find.text('Mở ứng dụng đầy đủ'), findsOneWidget);
    expect(find.text('Ngắt kết nối với máy mẹ'), findsOneWidget);

    await t.tap(find.byKey(const Key('parent-disconnect')));
    await t.pumpAndSettle();
    expect(session.mode, ConnectionMode.unset);
  });
}

class _Family implements FamilyPlatform {
  final queued = <String>[];
  final statuses = <String, String>{};

  @override
  Future<void> queueRequest(String kind, {int minutes = 0}) async {
    queued.add('$kind:$minutes');
    statuses[kind] = 'pending';
  }

  @override
  Future<Map<String, String>> requestStatuses() async => {...statuses};

  int syncs = 0;
  bool result = true;
  DateTime? lastSync;

  @override
  Future<DateTime?> lastSyncAt() async => lastSync;

  @override
  Future<bool> syncNow() async {
    syncs++;
    if (result) lastSync = DateTime.now();
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) async {}
}
