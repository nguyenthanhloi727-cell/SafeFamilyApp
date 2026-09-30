import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:safe_family_app/features/app_lock/app_lock_config.dart';
import 'package:safe_family_app/features/app_lock/data/app_lock_platform.dart';
import 'package:safe_family_app/features/app_lock/data/app_lock_store.dart';
import 'package:safe_family_app/features/app_lock/presentation/app_lock_controller.dart';

import '../../helpers/app_lock_fakes.dart';

const youtube = 'com.google.android.youtube';

void main() {
  late FakeAppLockPlatform platform;
  late FakeClock clock;
  late AppLockStore store;
  late List<String> disabledLog;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    platform = FakeAppLockPlatform();
    clock = FakeClock(DateTime(2026, 9, 30, 14, 0));
    store = AppLockStore(prefs: SharedPreferencesAsync());
    disabledLog = [];
  });

  /// Mỗi lần gọi = một lần mở SafeFamily (dùng chung kho + nền tảng).
  Future<AppLockController> openApp() async {
    final controller = AppLockController(
      platform: platform,
      store: store,
      clock: clock.call,
      onDisabled: (action) async => disabledLog.add(action),
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    return controller;
  }

  test('chặn / bỏ chặn', () async {
    final c = await openApp();
    expect(await c.setLocked(youtube, true), isTrue);
    expect(platform.blocked, {youtube});
    expect(c.isLocked(youtube), isTrue);
    expect(await c.setLocked(youtube, false), isTrue);
    expect(platform.blocked, isEmpty);
  });

  test('không cho chặn app được bảo vệ, gỡ nếu lỡ bị chặn', () async {
    platform.blocked.addAll({'com.android.settings', 'com.android.contacts'});
    final c = await openApp();
    expect(platform.blocked, isEmpty, reason: 'mở app là gỡ chặn ngay');
    expect(await c.setLocked('com.android.contacts', true), isFalse);
    expect(await c.setLocked('com.android.settings', true), isFalse);
    expect(platform.blocked, isEmpty);
  });

  test('danh sách app không có app được bảo vệ', () async {
    final c = await openApp();
    await c.loadApps();
    expect(
      c.apps!.map((a) => a.packageName),
      isNot(contains('com.android.contacts')),
    );
  });

  test('thiếu quyền thì không chặn được', () async {
    platform.perms = const AppLockPermissions(
      accessibility: false,
      exactAlarm: true,
      batteryUnrestricted: true,
    );
    final c = await openApp();
    expect(await c.setLocked(youtube, true), isFalse);
    expect(platform.blocked, isEmpty);
  });

  group('mở tạm $tempUnlockMinutes phút', () {
    test('bỏ chặn + hẹn chặn lại đúng giờ', () async {
      platform.blocked.add(youtube);
      final c = await openApp();
      final until = await c.unlockTemporarily(youtube);

      expect(until, clock.now.add(tempUnlockDuration));
      expect(platform.blocked, isEmpty);
      expect(platform.relocks, {youtube: until});
      expect(c.isLocked(youtube), isTrue, reason: 'vẫn tính là đang chặn');
      expect(c.unlockedUntil(youtube), until);
    });

    test('hết giờ → mở lại app thì bị chặn lại, xóa lịch', () async {
      platform.blocked.add(youtube);
      await (await openApp()).unlockTemporarily(youtube);

      clock.advance(tempUnlockDuration - const Duration(minutes: 1));
      final before = await openApp();
      expect(platform.blocked, isEmpty, reason: 'chưa hết giờ');
      expect(before.unlockedUntil(youtube), isNotNull);

      clock.advance(const Duration(minutes: 1));
      final after = await openApp();
      expect(platform.blocked, {youtube});
      expect(platform.relocks, isEmpty);
      expect(after.unlockedUntil(youtube), isNull);
      expect((await store.loadUnlocks()).isEmpty, isTrue);
    });

    test('app_blocker xóa lịch khi SafeFamily mở lại → đặt lại lịch', () async {
      platform.blocked.add(youtube);
      final until = await (await openApp()).unlockTemporarily(youtube);
      platform.relocks.clear(); // rescheduleAll() của app_blocker

      clock.advance(const Duration(minutes: 5));
      await openApp();
      expect(platform.relocks, {youtube: until});
      expect(platform.blocked, isEmpty);
    });

    test('không hẹn được lịch → giữ nguyên chặn', () async {
      platform.blocked.add(youtube);
      platform.failSchedule = true;
      final c = await openApp();
      await expectLater(c.unlockTemporarily(youtube), throwsStateError);
      expect(platform.blocked, {youtube});
      expect(c.unlockedUntil(youtube), isNull);
      expect((await store.loadUnlocks()).isEmpty, isTrue);
    });

    test('chặn lại ngay', () async {
      platform.blocked.add(youtube);
      final c = await openApp();
      await c.unlockTemporarily(youtube);
      await c.relockNow(youtube);
      expect(platform.blocked, {youtube});
      expect(platform.relocks, isEmpty);
    });

    test('tắt công tắc khi đang mở tạm → bỏ chặn hẳn, hủy lịch', () async {
      platform.blocked.add(youtube);
      final c = await openApp();
      await c.unlockTemporarily(youtube);
      await c.setLocked(youtube, false);
      expect(platform.relocks, isEmpty);
      expect(c.isLocked(youtube), isFalse);
    });

    test('sát nửa đêm → không mở tạm, vẫn chặn', () async {
      platform.blocked.add(youtube);
      clock.now = DateTime(2026, 9, 30, 23, 59, 10);
      final c = await openApp();
      expect(await c.unlockTemporarily(youtube), isNull);
      expect(platform.blocked, {youtube});
    });
  });

  group('kiểm tra quyền mỗi lần mở app', () {
    const off = AppLockPermissions(
      accessibility: false,
      exactAlarm: true,
      batteryUnrestricted: true,
    );

    test('đang chặn mà tắt Trợ năng → cảnh báo + ghi nhật ký 1 lần', () async {
      platform.blocked.add(youtube);
      expect((await openApp()).disabled, isFalse);

      platform.perms = off;
      final c = await openApp();
      expect(c.disabled, isTrue);
      expect(disabledLog, [
        'Khóa ứng dụng bị vô hiệu hóa: quyền Trợ năng bị tắt',
      ]);

      await openApp();
      expect(disabledLog, hasLength(1), reason: 'không ghi trùng');

      platform.perms = FakeAppLockPlatform.readyPermissions;
      expect((await openApp()).disabled, isFalse);
      platform.perms = off;
      await openApp();
      expect(disabledLog, hasLength(2), reason: 'tắt lần nữa thì ghi lại');
    });

    test('chưa chặn app nào → không cảnh báo', () async {
      platform.perms = off;
      final c = await openApp();
      expect(c.disabled, isFalse);
      expect(disabledLog, isEmpty);
    });
  });
}
