import 'package:flutter/material.dart';

import '../security/secure_store.dart';

/// Máy này dùng thế nào: một máy (local), máy mẹ, hay máy con.
enum ConnectionMode { unset, local, parent, child }

/// Vai trò + token đăng nhập + địa chỉ API. Token lưu trong [SecureStore]
/// (Android Keystore), không đưa vào SharedPreferences.
///
/// Chế độ `local` giữ nguyên cách app chạy một máy từ trước tới giờ.
class ConnectionSession extends ChangeNotifier {
  ConnectionSession({SecureStore? store})
    : _store = store ?? const FlutterSecureStore();

  /// TODO(verify): domain MonsterASP tạm (ftempurl), người dùng sửa được trên
  /// màn kết nối.
  static const defaultBaseUrl = 'https://shamixd-001-site1.ftempurl.com';

  /// Mặc định cũ (emulator). Máy đã lưu đúng địa chỉ này thì coi như chưa tự
  /// chỉnh, dùng mặc định mới, khỏi phải gỡ cài lại app.
  static const _legacyDefaultBaseUrls = {'http://10.0.2.2:5025'};

  static const _kMode = 'conn_mode';
  static const _kBaseUrl = 'conn_base_url';
  static const _kAccess = 'conn_access_token';
  static const _kRefresh = 'conn_refresh_token';
  static const _kDevice = 'conn_device_token';
  static const _kEmail = 'conn_email';
  static const _kDeviceId = 'conn_device_id';

  final SecureStore _store;
  bool _loaded = false;
  ConnectionMode _mode = ConnectionMode.unset;
  String _baseUrl = defaultBaseUrl;
  String? _accessToken;
  String? _refreshToken;
  String? _deviceToken;
  String? _email;
  int? _deviceId;

  bool get isLoaded => _loaded;
  ConnectionMode get mode => _mode;
  String get baseUrl => _baseUrl;
  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;
  String? get deviceToken => _deviceToken;
  String? get email => _email;
  int? get deviceId => _deviceId;

  /// Đã chọn vai trò chưa (chưa chọn → hiện màn chọn vai trò).
  bool get isChosen => _mode != ConnectionMode.unset;
  bool get isParentLoggedIn => _refreshToken != null;
  bool get isChildPaired => _deviceToken != null;

  Future<void> load() async {
    try {
      final mode = await _store.read(_kMode);
      _mode = ConnectionMode.values.firstWhere(
        (m) => m.name == mode,
        orElse: () => ConnectionMode.unset,
      );
      final saved = await _store.read(_kBaseUrl);
      if (saved == null || _legacyDefaultBaseUrls.contains(saved)) {
        _baseUrl = defaultBaseUrl;
        if (saved != null) await _write(_kBaseUrl, defaultBaseUrl);
      } else {
        _baseUrl = saved;
      }
      _accessToken = await _store.read(_kAccess);
      _refreshToken = await _store.read(_kRefresh);
      _deviceToken = await _store.read(_kDevice);
      _email = await _store.read(_kEmail);
      _deviceId = int.tryParse(await _store.read(_kDeviceId) ?? '');
    } catch (_) {
      // Không đọc được kho bảo mật: coi như chưa chọn, hỏi lại vai trò.
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> setMode(ConnectionMode mode) async {
    _mode = mode;
    await _write(_kMode, mode.name);
    notifyListeners();
  }

  Future<void> setBaseUrl(String url) async {
    _baseUrl = normalizeBaseUrl(url);
    await _write(_kBaseUrl, _baseUrl);
    notifyListeners();
  }

  Future<void> saveParentTokens({
    required String access,
    required String refresh,
    String? email,
  }) async {
    _accessToken = access;
    _refreshToken = refresh;
    if (email != null) _email = email;
    await _write(_kAccess, access);
    await _write(_kRefresh, refresh);
    if (email != null) await _write(_kEmail, email);
    notifyListeners();
  }

  Future<void> saveDevice({required String token, required int id}) async {
    _deviceToken = token;
    _deviceId = id;
    await _write(_kDevice, token);
    await _write(_kDeviceId, '$id');
    notifyListeners();
  }

  /// Về lại chọn vai trò: xóa mọi token. Nơi gọi phải đã qua khóa phụ huynh.
  Future<void> reset() async {
    _mode = ConnectionMode.unset;
    _accessToken = _refreshToken = _deviceToken = _email = null;
    _deviceId = null;
    for (final k in [
      _kMode,
      _kAccess,
      _kRefresh,
      _kDevice,
      _kEmail,
      _kDeviceId,
    ]) {
      try {
        await _store.delete(k);
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> _write(String key, String value) async {
    try {
      await _store.write(key, value);
    } catch (_) {
      // Lưu hỏng: phiên hiện tại vẫn chạy, lần mở sau đăng nhập lại.
    }
  }

  /// Bỏ khoảng trắng và dấu `/` cuối; thiếu giao thức thì coi là https.
  static String normalizeBaseUrl(String url) {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    if (u.isNotEmpty && !u.contains('://')) u = 'https://$u';
    return u;
  }
}

/// Đưa [ConnectionSession] xuống cây widget.
class ConnectionScope extends InheritedNotifier<ConnectionSession> {
  const ConnectionScope({
    super.key,
    required ConnectionSession session,
    required super.child,
  }) : super(notifier: session);

  static ConnectionSession? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ConnectionScope>()?.notifier;

  static ConnectionSession of(BuildContext context) {
    final s = maybeOf(context);
    assert(s != null, 'Thiếu ConnectionScope trên cây widget');
    return s!;
  }
}
