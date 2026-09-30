import 'package:safe_family_app/features/app_lock/data/app_lock_platform.dart';

/// app_blocker giả: lưu trong bộ nhớ, ghi lại lịch tự chặn lại.
class FakeAppLockPlatform implements AppLockPlatform {
  FakeAppLockPlatform({
    List<InstalledApp>? apps,
    Set<String>? blocked,
    this.perms = readyPermissions,
    this.protectedSet = const {'com.android.contacts'},
  }) : apps = apps ?? sampleApps,
       blocked = blocked ?? {};

  static const readyPermissions = AppLockPermissions(
    accessibility: true,
    exactAlarm: true,
    batteryUnrestricted: true,
  );

  static const sampleApps = [
    InstalledApp(packageName: 'com.google.android.youtube', name: 'YouTube'),
    InstalledApp(packageName: 'com.zing.zalo', name: 'Zalo'),
    InstalledApp(
      packageName: 'com.android.chrome',
      name: 'Chrome',
      isSystemApp: true,
    ),
    InstalledApp(packageName: 'com.android.contacts', name: 'Điện thoại'),
  ];

  List<InstalledApp> apps;
  final Set<String> blocked;
  AppLockPermissions perms;
  Set<String> protectedSet;

  /// package → giờ tự chặn lại.
  final relocks = <String, DateTime>{};
  bool failSchedule = false;
  final opened = <AppLockSetting>[];

  @override
  Future<List<InstalledApp>> installedApps() async => apps;

  @override
  Future<Set<String>> blockedApps() async => {...blocked};

  @override
  Future<void> block(List<String> packages) async => blocked.addAll(packages);

  @override
  Future<void> unblock(List<String> packages) async =>
      blocked.removeAll(packages);

  @override
  Future<void> scheduleRelock(String packageName, DateTime at) async {
    if (failSchedule) throw StateError('SCHEDULE_EXACT_ALARM bị tắt');
    relocks[packageName] = at;
  }

  @override
  Future<void> cancelRelock(String packageName) async =>
      relocks.remove(packageName);

  @override
  Future<Set<String>> scheduledRelocks() async => {...relocks.keys};

  @override
  Future<AppLockPermissions> permissions() async => perms;

  @override
  Future<Set<String>> protectedPackages() async => protectedSet;

  @override
  Future<bool> openSetting(AppLockSetting setting) async {
    opened.add(setting);
    return true;
  }
}

/// Đồng hồ giả chỉnh tay được.
class FakeClock {
  FakeClock(this.now);

  DateTime now;

  DateTime call() => now;

  void advance(Duration duration) => now = now.add(duration);
}
