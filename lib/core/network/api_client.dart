import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'connection_session.dart';

/// Lỗi gọi API. [status] = 0 khi không tới được máy chủ (mất mạng, sai địa chỉ).
class ApiException implements Exception {
  const ApiException(this.status, this.message);

  final int status;
  final String message;

  bool get isNetwork => status == 0;
  bool get isUnauthorized => status == 401;
  bool get isConflict => status == 409;

  @override
  String toString() => 'ApiException($status): $message';
}

class AuthResult {
  const AuthResult(this.accessToken, this.refreshToken, this.familyId);
  final String accessToken;
  final String refreshToken;
  final int familyId;
}

class PairingCode {
  const PairingCode(this.code, this.expiresAt);
  final String code;
  final DateTime expiresAt;
}

class ClaimResult {
  const ClaimResult(this.deviceToken, this.deviceId, this.deviceName);
  final String deviceToken;
  final int deviceId;
  final String deviceName;
}

class DeviceInfo {
  const DeviceInfo(this.id, this.name, this.lastSeenAt);
  final int id;
  final String name;
  final DateTime? lastSeenAt;
}

class PolicyInfo {
  const PolicyInfo(this.version, this.json);
  final int version;
  final String json;
}

class RemoteCommand {
  const RemoteCommand(this.id, this.type, this.payloadJson);
  final int id;
  final String type;
  final String payloadJson;
}

class LocationInfo {
  const LocationInfo(this.lat, this.lng, this.accuracy, this.time);
  final double lat;
  final double lng;
  final double accuracy;
  final DateTime time;
}

class GeofenceInfo {
  const GeofenceInfo({
    this.id = 0,
    required this.name,
    required this.lat,
    required this.lng,
    required this.radiusM,
  });
  final int id;
  final String name;
  final double lat;
  final double lng;
  final double radiusM;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'lat': lat,
    'lng': lng,
    'radiusM': radiusM,
  };
}

class GeofenceSet {
  const GeofenceSet(this.version, this.geofences);
  final int version;
  final List<GeofenceInfo> geofences;
}

class GeofenceEventInfo {
  const GeofenceEventInfo(this.id, this.name, this.type, this.time);
  final int id;
  final String name;

  /// `enter` hoặc `exit`.
  final String type;
  final DateTime time;
  bool get isExit => type == 'exit';
}

/// Server trả giờ UTC không kèm `Z`; thiếu thì thêm vào để không bị hiểu là giờ máy.
DateTime? parseServerTime(Object? value) {
  if (value is! String || value.isEmpty) return null;
  final hasZone = value.endsWith('Z') || RegExp(r'[+-]\d\d:\d\d$').hasMatch(value);
  return DateTime.tryParse(hasZone ? value : '${value}Z');
}

enum _Auth { none, parent, device }

/// Gọi API SafeFamily (xem docs/API_TIEN_TRINH.md). Việc của lớp này:
/// gắn token, tự làm mới access token của mẹ khi gặp 401, thử lại yêu cầu GET
/// khi mất mạng, và đổi mọi lỗi thành [ApiException] bằng tiếng Việt.
class ApiClient {
  ApiClient({
    required this.session,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
    this.retryDelay = const Duration(seconds: 1),
  }) : _http = client ?? http.Client();

  final ConnectionSession session;
  final Duration timeout;
  final Duration retryDelay;
  final http.Client _http;
  Future<bool>? _refreshing;

  // ---- Đăng nhập (mẹ) ----

  Future<AuthResult> register(
    String email,
    String password, {
    String? familyName,
  }) async => _saveAuth(
    email,
    await _send('POST', '/api/auth/register', {
      'email': email,
      'password': password,
      'familyName': familyName,
    }),
  );

  Future<AuthResult> login(String email, String password) async => _saveAuth(
    email,
    await _send('POST', '/api/auth/login', {
      'email': email,
      'password': password,
    }),
  );

  Future<AuthResult> _saveAuth(String email, Object? body) async {
    final m = body as Map<String, dynamic>;
    final r = AuthResult(
      m['accessToken'] as String,
      m['refreshToken'] as String,
      m['familyId'] as int,
    );
    await session.saveParentTokens(
      access: r.accessToken,
      refresh: r.refreshToken,
      email: email,
    );
    return r;
  }

  // ---- Ghép đôi ----

  Future<PairingCode> createPairingCode({String? deviceName}) async {
    final m = await _send('POST', '/api/pairing/code', {
      'deviceName': deviceName,
    }, auth: _Auth.parent) as Map<String, dynamic>;
    return PairingCode(
      m['code'] as String,
      DateTime.parse(m['expiresAt'] as String),
    );
  }

  /// Máy con nhập mã; thành công thì lưu token thiết bị vào [session].
  Future<ClaimResult> claimPairingCode(String code) async {
    final m = await _send('POST', '/api/pairing/claim', {
      'code': code,
    }) as Map<String, dynamic>;
    final r = ClaimResult(
      m['deviceToken'] as String,
      m['deviceId'] as int,
      m['deviceName'] as String,
    );
    await session.saveDevice(token: r.deviceToken, id: r.deviceId);
    return r;
  }

  // ---- Mẹ quản lý máy con ----

  Future<List<DeviceInfo>> listDevices() async {
    final list = await _send(
      'GET',
      '/api/devices',
      null,
      auth: _Auth.parent,
    ) as List<dynamic>;
    return [
      for (final e in list.cast<Map<String, dynamic>>())
        DeviceInfo(
          e['id'] as int,
          e['name'] as String,
          parseServerTime(e['lastSeenAt']),
        ),
    ];
  }

  Future<void> unpairDevice(int id) =>
      _send('DELETE', '/api/devices/$id', null, auth: _Auth.parent);

  Future<PolicyInfo> getPolicy(int deviceId) async => _policy(
    await _send(
      'GET',
      '/api/devices/$deviceId/policy',
      null,
      auth: _Auth.parent,
    ),
  );

  /// Lệch phiên bản → [ApiException.isConflict].
  Future<PolicyInfo> putPolicy(
    int deviceId,
    String json,
    int expectedVersion,
  ) async => _policy(
    await _send('PUT', '/api/devices/$deviceId/policy', {
      'json': json,
      'expectedVersion': expectedVersion,
    }, auth: _Auth.parent),
  );

  Future<void> sendCommand(int deviceId, String type, {String? payloadJson}) =>
      _send('POST', '/api/devices/$deviceId/commands', {
        'type': type,
        'payloadJson': payloadJson,
      }, auth: _Auth.parent);

  // ---- Vị trí và hàng rào địa lý (mẹ) ----

  /// Vị trí mới nhất; `null` nếu máy con chưa gửi lần nào.
  Future<LocationInfo?> getLastLocation(int deviceId) async {
    final m = await _send(
      'GET',
      '/api/devices/$deviceId/location',
      null,
      auth: _Auth.parent,
    );
    if (m is! Map<String, dynamic>) return null;
    return LocationInfo(
      (m['lat'] as num).toDouble(),
      (m['lng'] as num).toDouble(),
      (m['accuracy'] as num).toDouble(),
      parseServerTime(m['time'])!,
    );
  }

  Future<GeofenceSet> getGeofences(int deviceId) async => _geofenceSet(
    await _send(
      'GET',
      '/api/devices/$deviceId/geofences',
      null,
      auth: _Auth.parent,
    ),
  );

  /// Thay cả bộ hàng rào. Lệch phiên bản → [ApiException.isConflict].
  Future<GeofenceSet> putGeofences(
    int deviceId,
    List<GeofenceInfo> fences,
    int expectedVersion,
  ) async => _geofenceSet(
    await _send('PUT', '/api/devices/$deviceId/geofences', {
      'geofences': [for (final f in fences) f.toJson()],
      'expectedVersion': expectedVersion,
    }, auth: _Auth.parent),
  );

  Future<List<GeofenceEventInfo>> getGeofenceEvents(
    int deviceId, {
    int afterId = 0,
  }) async {
    final list = await _send(
      'GET',
      '/api/devices/$deviceId/geofence-events?afterId=$afterId',
      null,
      auth: _Auth.parent,
    ) as List<dynamic>;
    return [
      for (final e in list.cast<Map<String, dynamic>>())
        GeofenceEventInfo(
          (e['id'] as num).toInt(),
          e['geofenceName'] as String,
          e['type'] as String,
          parseServerTime(e['time'])!,
        ),
    ];
  }

  GeofenceSet _geofenceSet(Object? body) {
    final m = body as Map<String, dynamic>;
    return GeofenceSet(m['version'] as int, [
      for (final g in (m['geofences'] as List<dynamic>).cast<Map<String, dynamic>>())
        GeofenceInfo(
          id: g['id'] as int,
          name: g['name'] as String,
          lat: (g['lat'] as num).toDouble(),
          lng: (g['lng'] as num).toDouble(),
          radiusM: (g['radiusM'] as num).toDouble(),
        ),
    ]);
  }

  // ---- Máy con (polling) ----

  Future<PolicyInfo> fetchMyPolicy() async => _policy(
    await _send('GET', '/api/devices/me/policy', null, auth: _Auth.device),
  );

  Future<List<RemoteCommand>> fetchMyCommands() async {
    final list = await _send(
      'GET',
      '/api/devices/me/commands',
      null,
      auth: _Auth.device,
    ) as List<dynamic>;
    return [
      for (final e in list.cast<Map<String, dynamic>>())
        RemoteCommand(
          e['id'] as int,
          e['type'] as String,
          e['payloadJson'] as String,
        ),
    ];
  }

  Future<void> ackCommand(int id) => _send(
    'POST',
    '/api/devices/me/commands/$id/ack',
    null,
    auth: _Auth.device,
  );

  Future<void> postInstalledApps(List<({String package, String label})> apps) =>
      _send('POST', '/api/devices/me/apps', {
        'apps': [
          for (final a in apps) {'packageName': a.package, 'label': a.label},
        ],
      }, auth: _Auth.device);

  PolicyInfo _policy(Object? body) {
    final m = body as Map<String, dynamic>;
    return PolicyInfo(m['version'] as int, m['json'] as String);
  }

  // ---- Lõi ----

  Future<Object?> _send(
    String method,
    String path,
    Map<String, dynamic>? body, {
    _Auth auth = _Auth.none,
  }) async {
    var response = await _once(method, path, body, auth);
    if (response.statusCode == 401 && auth == _Auth.parent) {
      if (await _refreshAccessToken()) {
        response = await _once(method, path, body, auth);
      }
    }
    return _decode(response);
  }

  Future<http.Response> _once(
    String method,
    String path,
    Map<String, dynamic>? body,
    _Auth auth,
  ) async {
    final uri = Uri.parse('${session.baseUrl}$path');
    final headers = <String, String>{
      if (body != null) 'Content-Type': 'application/json',
      if (auth == _Auth.parent && session.accessToken != null)
        'Authorization': 'Bearer ${session.accessToken}',
      if (auth == _Auth.device && session.deviceToken != null)
        'Authorization': 'Bearer ${session.deviceToken}',
    };
    // Chỉ GET được thử lại: POST/PUT thử lại có thể tạo trùng (mã ghép, lệnh).
    final attempts = method == 'GET' ? 3 : 1;
    for (var i = 1; ; i++) {
      try {
        final request = http.Request(method, uri)..headers.addAll(headers);
        if (body != null) request.body = jsonEncode(body);
        final streamed = await _http.send(request).timeout(timeout);
        return await http.Response.fromStream(streamed);
      } on TimeoutException {
        if (i >= attempts) {
          throw const ApiException(0, 'Máy chủ không phản hồi.');
        }
      } on http.ClientException {
        if (i >= attempts) {
          throw const ApiException(0, 'Không kết nối được máy chủ.');
        }
      } on FormatException {
        throw const ApiException(0, 'Địa chỉ máy chủ không hợp lệ.');
      }
      await Future<void>.delayed(retryDelay * i);
    }
  }

  /// Gộp nhiều yêu cầu 401 cùng lúc vào một lần làm mới token.
  Future<bool> _refreshAccessToken() =>
      _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);

  Future<bool> _doRefresh() async {
    final refresh = session.refreshToken;
    if (refresh == null) return false;
    try {
      final r = await _once('POST', '/api/auth/refresh', {
        'refreshToken': refresh,
      }, _Auth.none);
      if (r.statusCode != 200) return false;
      final m = jsonDecode(r.body) as Map<String, dynamic>;
      await session.saveParentTokens(
        access: m['accessToken'] as String,
        refresh: m['refreshToken'] as String,
      );
      return true;
    } on ApiException {
      return false;
    }
  }

  Object? _decode(http.Response r) {
    if (r.statusCode >= 200 && r.statusCode < 300) {
      if (r.body.isEmpty) return null;
      return jsonDecode(r.body);
    }
    String? serverMessage;
    try {
      final m = jsonDecode(r.body);
      if (m is Map<String, dynamic>) serverMessage = m['error'] as String?;
    } catch (_) {}
    throw ApiException(
      r.statusCode,
      serverMessage ?? _defaultMessage(r.statusCode),
    );
  }

  static String _defaultMessage(int status) => switch (status) {
    400 => 'Thông tin chưa hợp lệ.',
    401 => 'Phiên đăng nhập hết hạn, hãy đăng nhập lại.',
    403 => 'Tài khoản này không được phép làm việc đó.',
    404 => 'Không tìm thấy.',
    409 => 'Dữ liệu đã đổi ở nơi khác.',
    429 => 'Thử quá nhiều lần, hãy đợi một lúc.',
    _ => 'Máy chủ gặp lỗi ($status).',
  };

  void close() => _http.close();
}
