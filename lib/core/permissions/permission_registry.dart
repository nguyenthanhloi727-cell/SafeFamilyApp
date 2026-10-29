import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Một quyền SafeFamily thật sự dùng (đã đối chiếu AndroidManifest + code).
enum AppPermission {
  accessibility('accessibility', 'Trợ năng (chặn ứng dụng)'),
  settingsGuard('settings_guard', 'Trợ năng (bảo vệ màn Cài đặt)'),
  usageAccess('usage_access', 'Truy cập dữ liệu sử dụng'),
  notifications('notifications', 'Thông báo'),
  exactAlarm('exact_alarm', 'Báo thức chính xác'),
  battery('battery', 'Bỏ tối ưu pin'),
  deviceAdmin('device_admin', 'Quản trị thiết bị (chống gỡ app)'),
  microphone('microphone', 'Micro (báo thức bằng giọng nói)');

  const AppPermission(this.id, this.label);

  /// Trùng khóa phía Kotlin (`permissionsChannel`).
  final String id;
  final String label;
}

/// Lớp nói chuyện với Android (kênh `safefamily/permissions`).
abstract interface class PermissionPlatform {
  /// Trạng thái mọi quyền, khóa là [AppPermission.id].
  Future<Map<String, bool>> status();

  /// Mở đúng trang Cài đặt của quyền. `false` nếu máy không mở được.
  Future<bool> openSettings(AppPermission permission);

  /// Tắt thẳng Quản trị thiết bị (`removeActiveAdmin`). `true` nếu đã tắt.
  Future<bool> removeDeviceAdmin();
}

class MethodChannelPermissions implements PermissionPlatform {
  const MethodChannelPermissions();

  static const _channel = MethodChannel('safefamily/permissions');

  @override
  Future<Map<String, bool>> status() async {
    try {
      return await _channel.invokeMapMethod<String, bool>('status') ?? const {};
    } on PlatformException catch (error) {
      debugPrint('Quyền: không đọc được trạng thái ($error)');
      return const {};
    } on MissingPluginException {
      return const {}; // Không phải Android (test).
    }
  }

  @override
  Future<bool> openSettings(AppPermission permission) async {
    try {
      return await _channel.invokeMethod<bool>('openSettings', {
            'id': permission.id,
          }) ??
          false;
    } on PlatformException catch (error) {
      debugPrint('Quyền: không mở được ${permission.id} ($error)');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> removeDeviceAdmin() async {
    try {
      return await _channel.invokeMethod<bool>('removeDeviceAdmin') ?? false;
    } on PlatformException catch (error) {
      debugPrint('Quyền: không tắt được Quản trị thiết bị ($error)');
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

/// Trạng thái một quyền tại lần kiểm tra gần nhất.
class PermissionEntry {
  const PermissionEntry({required this.permission, required this.granted});

  final AppPermission permission;
  final bool granted;

  String get id => permission.id;
  String get name => permission.label;
}

/// Gom mọi quyền về một chỗ, dùng chung cho màn Quyền, wizard, màn "Đang cản trở".
///
/// Tự kiểm tra lại mọi quyền mỗi khi app `resumed` (vừa quay về từ Cài đặt máy)
/// nên bật/tắt quyền ngoài Cài đặt thì UI đổi theo, không cần khởi động lại.
class PermissionRegistry extends ChangeNotifier with WidgetsBindingObserver {
  PermissionRegistry({PermissionPlatform? platform})
    : _platform = platform ?? const MethodChannelPermissions();

  final PermissionPlatform _platform;

  Map<String, bool> _status = const {};
  bool _loaded = false;
  bool _disposed = false;
  bool _started = false;

  /// Đã đọc trạng thái ít nhất một lần.
  bool get isLoaded => _loaded;

  /// Mọi quyền đã đăng ký, theo thứ tự khai báo.
  List<PermissionEntry> get entries => [
    for (final p in AppPermission.values)
      PermissionEntry(permission: p, granted: _status[p.id] ?? false),
  ];

  /// Các quyền đang bật (đang cấp cho SafeFamily).
  List<PermissionEntry> get granted => [
    for (final e in entries)
      if (e.granted) e,
  ];

  /// Các quyền còn thiếu.
  List<PermissionEntry> get missing => [
    for (final e in entries)
      if (!e.granted) e,
  ];

  bool isGranted(AppPermission permission) => _status[permission.id] ?? false;

  /// Gọi 1 lần khi app chạy: đọc trạng thái và theo dõi `resumed`.
  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  /// Đọc lại trạng thái mọi quyền.
  Future<void> refresh() async {
    final next = await _platform.status();
    if (_disposed) return;
    final changed = !_loaded || !mapEquals(_status, next);
    _status = next;
    _loaded = true;
    if (changed) notifyListeners();
  }

  /// Mở trang Cài đặt của [permission]. Việc xác thực phụ huynh (khi tắt) do
  /// nơi gọi làm trước.
  Future<bool> openSettings(AppPermission permission) =>
      _platform.openSettings(permission);

  /// Tắt thẳng Quản trị thiết bị rồi đọc lại. Nơi gọi xác thực phụ huynh trước.
  Future<bool> removeDeviceAdmin() async {
    final removed = await _platform.removeDeviceAdmin();
    await refresh();
    return removed;
  }

  @override
  void dispose() {
    _disposed = true;
    if (_started) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

/// Đưa [PermissionRegistry] xuống cây widget.
class PermissionRegistryScope extends InheritedNotifier<PermissionRegistry> {
  const PermissionRegistryScope({
    super.key,
    required PermissionRegistry registry,
    required super.child,
  }) : super(notifier: registry);

  static PermissionRegistry of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<PermissionRegistryScope>();
    assert(scope != null, 'Thiếu PermissionRegistryScope trên cây widget');
    return scope!.notifier!;
  }

  static PermissionRegistry? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<PermissionRegistryScope>()
      ?.notifier;
}
