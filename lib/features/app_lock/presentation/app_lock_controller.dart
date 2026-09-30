import 'dart:async';

import 'package:flutter/widgets.dart';

import '../app_lock_config.dart';
import '../data/app_lock_platform.dart';
import '../data/app_lock_store.dart';
import '../domain/protected_apps.dart';
import '../domain/temp_unlock.dart';

/// Trạng thái Khóa ứng dụng dùng chung (Trang chủ, Quản lý thiết bị).
///
/// - Chặn / bỏ chặn qua app_blocker; không bao giờ chặn [ProtectedApps].
/// - Mở tạm: bỏ chặn + hẹn app_blocker tự chặn lại (chạy cả khi SafeFamily
///   đã tắt); khi SafeFamily đang mở thì thêm một Timer.
/// - Mỗi lần mở app / quay lại app: kiểm tra quyền, chặn lại app hết giờ mở
///   tạm, đặt lại lịch tự chặn (app_blocker xóa lịch này mỗi lần app chạy).
class AppLockController extends ChangeNotifier {
  AppLockController({
    required this._platform,
    AppLockStore? store,
    DateTime Function()? clock,
    this.onDisabled,
  }) : _store = store ?? AppLockStore(),
       _clock = clock ?? DateTime.now;

  final AppLockPlatform _platform;
  final AppLockStore _store;
  final DateTime Function() _clock;

  /// Ghi nhật ký khi khóa ứng dụng bị vô hiệu hóa (thiếu quyền).
  final Future<void> Function(String action)? onDisabled;

  bool _loaded = false;
  AppLockPermissions? _permissions;
  Set<String> _protected = const {};
  Set<String> _blocked = {};
  TempUnlocks _unlocks = const TempUnlocks();
  List<InstalledApp>? _apps;
  bool _appsFailed = false;
  final _busy = <String>{};

  Timer? _timer;
  AppLifecycleListener? _lifecycle;
  Future<void> _queue = Future.value();
  bool _disposed = false;

  bool get isLoaded => _loaded;
  AppLockPermissions? get permissions => _permissions;
  bool get ready => _permissions?.ready ?? false;

  /// Danh sách app đã cài (`null` = chưa tải xong).
  List<InstalledApp>? get apps => _apps;
  bool get appsFailed => _appsFailed;

  /// Có app đang bị chặn hoặc đang mở tạm.
  bool get hasLocks => _blocked.isNotEmpty || !_unlocks.isEmpty;

  /// Số app đang bị chặn (kể cả đang mở tạm).
  int get lockedCount => {..._blocked, ..._unlocks.packages}.length;

  /// Đang chặn app mà thiếu quyền → chặn không có tác dụng (cảnh báo đỏ).
  bool get disabled => _permissions != null && !ready && hasLocks;

  bool isProtected(String packageName) =>
      ProtectedApps.isProtected(packageName, _protected);

  /// Bị chặn (kể cả đang mở tạm).
  bool isLocked(String packageName) =>
      _blocked.contains(packageName) || _unlocks.contains(packageName);

  /// Đang mở tạm tới lúc nào (`null` = không mở tạm).
  DateTime? unlockedUntil(String packageName) => _unlocks.untilOf(packageName);

  bool isBusy(String packageName) => _busy.contains(packageName);

  Future<bool> openSetting(AppLockSetting setting) =>
      _platform.openSetting(setting);

  /// Gọi 1 lần khi app chạy.
  void start() {
    _lifecycle ??= AppLifecycleListener(onResume: refresh);
    refresh();
  }

  /// Kiểm tra quyền + đối soát app mở tạm. Gọi khi mở app / quay lại app.
  Future<void> refresh() => _serial(() async {
    try {
      _permissions = await _platform.permissions();
      _protected = await _platform.protectedPackages();
      _unlocks = await _store.loadUnlocks();
      _blocked = await _platform.blockedApps();
      final wrong = [..._blocked.where(isProtected)];
      if (wrong.isNotEmpty) {
        await _platform.unblock(wrong);
        _blocked.removeAll(wrong);
      }
      await _reconcile();
      await _checkDisabled();
    } catch (error) {
      debugPrint('Khóa ứng dụng: không kiểm tra được ($error)');
    }
    _loaded = true;
    _notify();
  });

  Future<void> loadApps() async {
    if (_appsFailed) {
      _appsFailed = false; // bấm Thử lại → hiện lại vòng chờ
      _notify();
    }
    try {
      _apps = [
        for (final app in await _platform.installedApps())
          if (!isProtected(app.packageName)) app,
      ];
    } catch (error) {
      debugPrint('Khóa ứng dụng: không lấy được danh sách app ($error)');
      _appsFailed = true;
    }
    _notify();
  }

  /// Chặn / bỏ chặn hẳn. Trả về `false` nếu không làm được.
  Future<bool> setLocked(String packageName, bool locked) => _serial(() async {
    if (locked && (isProtected(packageName) || !ready)) return false;
    _busy.add(packageName);
    _notify();
    try {
      if (locked) {
        await _platform.block([packageName]);
        _blocked.add(packageName);
      } else {
        if (_unlocks.contains(packageName)) {
          await _platform.cancelRelock(packageName);
          await _saveUnlocks(_unlocks.without(packageName));
        }
        await _platform.unblock([packageName]);
        _blocked.remove(packageName);
      }
      return true;
    } catch (error) {
      debugPrint('Khóa ứng dụng: lỗi chặn/bỏ chặn ($error)');
      return false;
    } finally {
      _busy.remove(packageName);
      _armTimer();
      _notify();
    }
  });

  /// Mở tạm [tempUnlockDuration]. Trả về lúc tự chặn lại; `null` nếu sát
  /// nửa đêm. Lỗi nền tảng → ném ra, app vẫn bị chặn.
  Future<DateTime?> unlockTemporarily(String packageName) => _serial(() async {
    final until = tempUnlockExpiry(_clock(), tempUnlockDuration);
    if (until == null || !_blocked.contains(packageName)) return null;
    _busy.add(packageName);
    _notify();
    try {
      // Lưu hạn + hẹn chặn lại TRƯỚC khi bỏ chặn: lỗi giữa chừng thì app
      // vẫn bị chặn, không bị mở vô thời hạn.
      await _saveUnlocks(_unlocks.withUnlock(packageName, until));
      try {
        await _platform.scheduleRelock(packageName, until);
      } catch (_) {
        await _saveUnlocks(_unlocks.without(packageName));
        rethrow;
      }
      await _platform.unblock([packageName]);
      _blocked.remove(packageName);
      return until;
    } finally {
      _busy.remove(packageName);
      _armTimer();
      _notify();
    }
  });

  /// Chặn lại ngay app đang mở tạm.
  Future<void> relockNow(String packageName) => _serial(() async {
    _busy.add(packageName);
    _notify();
    try {
      await _relock(packageName);
    } finally {
      _busy.remove(packageName);
      _armTimer();
      _notify();
    }
  });

  // ---------------------------------------------------------------- nội bộ

  Future<void> _reconcile() async {
    for (final packageName in _unlocks.expired(_clock())) {
      await _relock(packageName);
    }
    if (!_unlocks.isEmpty) {
      final scheduled = await _platform.scheduledRelocks();
      for (final packageName in _unlocks.packages) {
        if (!scheduled.contains(packageName)) {
          await _platform.scheduleRelock(
            packageName,
            _unlocks.untilOf(packageName)!,
          );
        }
      }
    }
    _armTimer();
  }

  Future<void> _relock(String packageName) async {
    // Xóa lịch trước: app_blocker bỏ chặn khi xóa lịch đang chạy.
    await _platform.cancelRelock(packageName);
    await _platform.block([packageName]);
    _blocked.add(packageName);
    await _saveUnlocks(_unlocks.without(packageName));
  }

  Future<void> _saveUnlocks(TempUnlocks unlocks) async {
    _unlocks = unlocks;
    await _store.saveUnlocks(unlocks);
  }

  void _armTimer() {
    _timer?.cancel();
    final now = _clock();
    final next = _unlocks.nextExpiry(now);
    if (next == null || _disposed) return;
    _timer = Timer(
      next.difference(now),
      () => _serial(() async {
        try {
          await _reconcile();
        } catch (error) {
          debugPrint('Khóa ứng dụng: không chặn lại được ($error)');
        }
        _notify();
      }),
    );
  }

  Future<void> _checkDisabled() async {
    final logged = await _store.disabledLogged();
    if (disabled && !logged) {
      final permissions = _permissions!;
      final missing = [
        if (!permissions.accessibility) 'quyền Trợ năng bị tắt',
        if (!permissions.exactAlarm) 'quyền Báo thức & lời nhắc bị tắt',
      ].join(', ');
      await onDisabled?.call('Khóa ứng dụng bị vô hiệu hóa: $missing');
      await _store.setDisabledLogged(true);
    } else if (ready && logged) {
      await _store.setDisabledLogged(false);
    }
  }

  /// Chạy lần lượt: thao tác sau chờ thao tác trước xong.
  Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _queue.then((_) => operation());
    _queue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _lifecycle?.dispose();
    super.dispose();
  }
}

/// Đưa [AppLockController] xuống cây widget.
class AppLockScope extends InheritedNotifier<AppLockController> {
  const AppLockScope({
    super.key,
    required AppLockController controller,
    required super.child,
  }) : super(notifier: controller);

  /// `null` khi không có (ví dụ test một màn riêng lẻ).
  static AppLockController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppLockScope>()?.notifier;
}
