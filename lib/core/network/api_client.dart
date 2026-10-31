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

  /// 403: với vị trí là "mẹ đã tắt chia sẻ" (API-11).
  bool get isForbidden => status == 403;

  @override
  String toString() => 'ApiException($status): $message';
}

class AuthResult {
  const AuthResult(this.accessToken, this.refreshToken, this.familyId);
  final String accessToken;
  final String refreshToken;
  final int familyId;
}

class FamilyMember {
  const FamilyMember(this.id, this.email, this.isOwner, this.isMe);
  final int id;
  final String email;
  final bool isOwner;
  final bool isMe;
}

class FamilyInfo {
  const FamilyInfo(this.name, this.isOwner, this.members);
  final String name;
  final bool isOwner;
  final List<FamilyMember> members;

  factory FamilyInfo.fromJson(Map<String, dynamic> m) => FamilyInfo(
    m['name'] as String,
    m['isOwner'] as bool,
    [
      for (final x in m['members'] as List)
        FamilyMember(
          (x as Map<String, dynamic>)['id'] as int,
          x['email'] as String,
          x['isOwner'] as bool,
          x['isMe'] as bool,
        ),
    ],
  );
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

/// Thông tin máy con tự xem (`GET /api/devices/me`, API-01). Không có email mẹ.
class DeviceSelfInfo {
  const DeviceSelfInfo(this.name, this.familyName, this.policyVersion);
  final String name;
  final String familyName;
  final int policyVersion;
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

/// App máy con đang mở tạm và giờ chặn lại (giờ máy con báo, ước lượng).
class TempUnlockInfo {
  const TempUnlockInfo(this.package, this.until);
  final String package;
  final DateTime until;
}

/// Trạng thái máy con do chính nó báo (`GET /api/devices/{id}/status`).
/// [reportedAt] `null` = máy con chưa báo lần nào (các trường khác chỉ là mặc định).
class DeviceStatusInfo {
  const DeviceStatusInfo({
    this.lastSeenAt,
    this.reportedAt,
    this.batteryPercent,
    this.policyVersion = 0,
    this.isPaused = false,
    this.studyActive = false,
    this.permissionsMissing = const [],
    this.appVersion,
    this.tempUnlocked = const [],
  });

  final DateTime? lastSeenAt;
  final DateTime? reportedAt;
  final int? batteryPercent;
  final int policyVersion;
  final bool isPaused;
  final bool studyActive;
  final List<String> permissionsMissing;
  final String? appVersion;
  final List<TempUnlockInfo> tempUnlocked;

  bool get hasReported => reportedAt != null;
}

/// Trạng thái một lệnh mẹ đã gửi.
enum CommandState {
  /// Máy con chưa xác nhận, còn trong hạn 24 giờ.
  pending,

  /// Máy con đã thực hiện và xác nhận.
  done,

  /// Quá 24 giờ mà máy con chưa nhận: server không giao nữa.
  expired,
}

/// Một lệnh trong `GET /api/devices/{id}/commands`.
class CommandInfo {
  const CommandInfo({
    required this.id,
    required this.type,
    required this.payloadJson,
    required this.createdAt,
    this.doneAt,
  });

  /// Khớp `CommandRules.MaxAge` ở server.
  static const maxAge = Duration(hours: 24);

  final int id;
  final String type;
  final String payloadJson;
  final DateTime createdAt;
  final DateTime? doneAt;

  CommandState stateAt(DateTime now) {
    if (doneAt != null) return CommandState.done;
    return now.difference(createdAt) > maxAge
        ? CommandState.expired
        : CommandState.pending;
  }
}

/// Loại yêu cầu của máy con (khớp `RequestRules` ở server).
abstract final class RequestKind {
  static const extraTime = 'extra_time';
  static const studyDone = 'study_done';
}

/// Một yêu cầu của máy con (`GET /api/devices/{id}/requests`). Chỉ có loại và số phút xin.
class ChildRequestInfo {
  const ChildRequestInfo({
    required this.id,
    required this.deviceId,
    required this.kind,
    required this.minutes,
    required this.status,
    required this.createdAt,
    this.decidedAt,
  });

  /// Số phút duyệt tối đa một lần (khớp `CommandRules.MaxExtraMinutes`).
  static const maxApproveMinutes = 120;

  final int id;
  final int deviceId;
  final String kind;

  /// Số phút con xin; `null` với `study_done`.
  final int? minutes;

  /// `pending` | `approved` | `rejected`.
  final String status;
  final DateTime createdAt;
  final DateTime? decidedAt;

  bool get isPending => status == 'pending';

  /// Số phút mẹ duyệt: số con xin, không quá [maxApproveMinutes].
  int get approveMinutes => (minutes ?? 0).clamp(1, maxApproveMinutes);
}

/// Trạng thái duyệt app mới cài (khớp `AppRules` ở server).
abstract final class AppStatus {
  static const isNew = 'new';
  static const allowed = 'allowed';
  static const blocked = 'blocked';
}

/// Một app của máy con (`GET /api/devices/{id}/apps`). Chỉ có tên + tên gói + trạng thái duyệt.
class InstalledAppInfo {
  const InstalledAppInfo({
    required this.id,
    required this.packageName,
    required this.label,
    required this.status,
    this.firstSeenAt,
    this.decidedAt,
  });

  final int id;
  final String packageName;
  final String label;

  /// `new` | `allowed` | `blocked` (xem [AppStatus]).
  final String status;
  final DateTime? firstSeenAt;
  final DateTime? decidedAt;
}

/// Phút dùng máy của một ngày do máy con báo (`GET /api/devices/{id}/usage`, API-08). Chỉ phút theo app.
class UsageDayInfo {
  const UsageDayInfo({
    required this.date,
    required this.totalMinutes,
    this.blocks = 0,
    this.apps = const {},
  });

  /// Ngày theo lịch máy con (00:00).
  final DateTime date;
  final int totalMinutes;
  final int blocks;

  /// `packageName -> phút`.
  final Map<String, int> apps;
}

/// Loại cảnh báo tamper / mất kết nối (khớp `AlertRules` ở server, API-10).
abstract final class AlertKind {
  static const timeChanged = 'time_changed';
  static const appUninstallAttempt = 'app_uninstall_attempt';
  static const accessibilityOff = 'accessibility_off';
  static const deviceAdminOff = 'device_admin_off';
  static const permissionMissing = 'permission_missing';
  static const offline = 'offline';
}

/// Một cảnh báo của máy con (`GET /api/devices/{id}/alerts`). Chỉ có loại, mã/số ngắn và thời điểm.
class AlertInfo {
  const AlertInfo({
    required this.id,
    required this.kind,
    required this.createdAt,
    this.detail,
    this.readAt,
  });

  final int id;
  final String kind;

  /// Mã/số ngắn tùy loại: phút lệch giờ, id quyền, số giờ mất kết nối... Có thể `null`.
  final String? detail;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isUnread => readAt == null;
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
  final hasZone =
      value.endsWith('Z') || RegExp(r'[+-]\d\d:\d\d$').hasMatch(value);
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

  /// Đăng xuất thật (API-03): thu hồi refresh token trên server rồi xóa phiên cục bộ ([ConnectionSession.reset]).
  /// Không tới được server (mất mạng) thì VẪN xóa phiên cục bộ và trả `false`: refresh token cũ còn hiệu lực
  /// trên server đến khi hết hạn 60 ngày, nơi gọi nên báo cho mẹ biết. Nơi gọi phải qua `ParentGate` trước.
  Future<bool> logout() async {
    final refresh = session.refreshToken;
    var revoked = refresh == null;
    if (refresh != null) {
      try {
        await _send('POST', '/api/auth/logout', {'refreshToken': refresh});
        revoked = true;
      } on ApiException {
        revoked = false;
      }
    }
    await session.reset();
    return revoked;
  }

  /// Đổi mật khẩu (API-03). Sai mật khẩu cũ → [ApiException.isForbidden]. Phiên này được giữ, các phiên khác bị đăng xuất.
  /// Nơi gọi phải qua `ParentGate` trước.
  Future<void> changePassword(String current, String next) => _send(
    'POST',
    '/api/auth/change-password',
    {
      'currentPassword': current,
      'newPassword': next,
      'refreshToken': session.refreshToken,
    },
    auth: _Auth.parent,
  );

  /// Xóa vĩnh viễn tài khoản và mọi dữ liệu gia đình (API-03), xong thì xóa phiên cục bộ.
  /// Sai mật khẩu → [ApiException.isForbidden]. Nơi gọi phải qua `ParentGate` + hộp xác nhận.
  Future<void> deleteAccount(String password) async {
    await _send('DELETE', '/api/auth/account', {
      'password': password,
      'confirm': true,
    }, auth: _Auth.parent);
    await session.reset();
  }

  /// Xin mã đặt lại mật khẩu qua email (API-03). Server luôn trả thành công dù email có tồn tại hay không.
  Future<void> forgotPassword(String email) =>
      _send('POST', '/api/auth/forgot-password', {'email': email});

  /// Đặt mật khẩu mới bằng mã 6 số trong thư. Mã sai/hết hạn → [ApiException] 400.
  Future<void> resetPassword(String email, String code, String newPassword) =>
      _send('POST', '/api/auth/reset-password', {
        'email': email,
        'code': code,
        'newPassword': newPassword,
      });

  // ---- Người giám hộ thứ 2 (API-02). Chưa có màn hình: TODO(verify) làm UI ở task riêng ----

  Future<FamilyInfo> family() async => FamilyInfo.fromJson(
    await _send('GET', '/api/family', null, auth: _Auth.parent)
        as Map<String, dynamic>,
  );

  /// Chủ tạo mã mời 8 số (30 phút, một lần). Không phải chủ → 403; đã đủ 2 người → 409.
  /// Nơi gọi phải qua `ParentGate` trước.
  Future<PairingCode> inviteGuardian() async {
    final m = await _send('POST', '/api/family/invite', {}, auth: _Auth.parent)
        as Map<String, dynamic>;
    return PairingCode(
      m['code'] as String,
      DateTime.parse(m['expiresAt'] as String),
    );
  }

  /// Người được mời đăng ký tài khoản mới bằng mã và vào gia đình của chủ mã; lưu token như [register].
  Future<AuthResult> joinFamily(String code, String email, String password) async =>
      _saveAuth(
        email,
        await _send('POST', '/api/family/join', {
          'code': code,
          'email': email,
          'password': password,
        }),
      );

  /// Chủ xóa người giám hộ khác. Nơi gọi phải qua `ParentGate` + hộp xác nhận.
  Future<void> removeGuardian(int parentId) => _send(
    'DELETE',
    '/api/family/members/$parentId',
    null,
    auth: _Auth.parent,
  );

  /// Người giám hộ thứ 2 tự rời gia đình, xong thì xóa phiên cục bộ. Nơi gọi phải qua `ParentGate` + hộp xác nhận.
  Future<void> leaveFamily() async {
    await _send('POST', '/api/family/leave', {}, auth: _Auth.parent);
    await session.reset();
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

  /// Mẹ đổi tên máy con (API-01). Nơi gọi phải qua `ParentGate` trước. Trả về tên server đã lưu (đã cắt khoảng trắng).
  Future<String> renameDevice(int id, String name) async {
    final m = await _send(
      'PATCH',
      '/api/devices/$id',
      {'name': name},
      auth: _Auth.parent,
    );
    return m is Map<String, dynamic> ? m['name'] as String : name.trim();
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

  /// Trạng thái máy con (pin, tạm dừng, quyền thiếu...). Chưa báo lần nào → `hasReported == false`.
  Future<DeviceStatusInfo> getDeviceStatus(int deviceId) async {
    final m = await _send(
      'GET',
      '/api/devices/$deviceId/status',
      null,
      auth: _Auth.parent,
    );
    if (m is! Map<String, dynamic>) return const DeviceStatusInfo();
    return DeviceStatusInfo(
      lastSeenAt: parseServerTime(m['lastSeenAt']),
      reportedAt: parseServerTime(m['reportedAt']),
      batteryPercent: (m['batteryPercent'] as num?)?.toInt(),
      policyVersion: (m['policyVersion'] as num?)?.toInt() ?? 0,
      isPaused: m['isPaused'] == true,
      studyActive: m['studyActive'] == true,
      permissionsMissing: [
        for (final p in (m['permissionsMissing'] as List<dynamic>? ?? const []))
          if (p is String) p,
      ],
      appVersion: m['appVersion'] as String?,
      tempUnlocked: [
        for (final t in (m['tempUnlocked'] as List<dynamic>? ?? const []))
          if (t is Map<String, dynamic> &&
              t['package'] is String &&
              parseServerTime(t['until']) != null)
            TempUnlockInfo(
              t['package'] as String,
              parseServerTime(t['until'])!,
            ),
      ],
    );
  }

  /// 50 lệnh gần nhất, mới nhất trước.
  Future<List<CommandInfo>> getCommands(int deviceId) async {
    final list = await _send(
      'GET',
      '/api/devices/$deviceId/commands',
      null,
      auth: _Auth.parent,
    ) as List<dynamic>;
    return [
      for (final e in list.cast<Map<String, dynamic>>())
        CommandInfo(
          id: (e['id'] as num).toInt(),
          type: e['type'] as String,
          payloadJson: e['payloadJson'] as String? ?? '{}',
          createdAt: parseServerTime(e['createdAt'])!,
          doneAt: parseServerTime(e['doneAt']),
        ),
    ];
  }

  /// Yêu cầu của máy con, mới nhất trước. [status] `pending` để chỉ lấy việc đang chờ mẹ duyệt.
  Future<List<ChildRequestInfo>> getRequests(
    int deviceId, {
    String? status,
  }) async {
    final query = status == null ? '' : '?status=$status';
    final list = await _send(
      'GET',
      '/api/devices/$deviceId/requests$query',
      null,
      auth: _Auth.parent,
    ) as List<dynamic>;
    return [
      for (final e in list.cast<Map<String, dynamic>>())
        ChildRequestInfo(
          id: (e['id'] as num).toInt(),
          deviceId: (e['deviceId'] as num).toInt(),
          kind: e['kind'] as String,
          minutes: _requestMinutes(e['payload']),
          status: e['status'] as String,
          createdAt: parseServerTime(e['createdAt'])!,
          decidedAt: parseServerTime(e['decidedAt']),
        ),
    ];
  }

  /// Mẹ duyệt/từ chối; server tự tạo lệnh cho máy con. Đã quyết định rồi hoặc hết hạn → [ApiException.isConflict].
  /// [minutes] chỉ dùng khi duyệt `extra_time` (bỏ trống = số phút con xin).
  Future<void> decideRequest(int id, {required bool approve, int? minutes}) =>
      _send('PUT', '/api/requests/$id', {
        'decision': approve ? 'approved' : 'rejected',
        'minutes': ?minutes,
      }, auth: _Auth.parent);

  /// Cảnh báo của máy con, cũ trước, tối đa 100. [afterId] = 0 (mặc định): 100 cảnh báo MỚI nhất; lớn hơn 0: các
  /// cảnh báo kế sau mốc đó (dò theo con trỏ không sót). Dòng hỏng bị bỏ qua.
  Future<List<AlertInfo>> getAlerts(int deviceId, {int afterId = 0}) async {
    final query = afterId > 0 ? '?afterId=$afterId' : '';
    final list = await _send(
      'GET',
      '/api/devices/$deviceId/alerts$query',
      null,
      auth: _Auth.parent,
    ) as List<dynamic>;
    final out = <AlertInfo>[];
    for (final e in list) {
      if (e is! Map<String, dynamic>) continue;
      final id = e['id'];
      final kind = e['kind'];
      final createdAt = parseServerTime(e['createdAt']);
      if (id is! num || kind is! String || createdAt == null) continue;
      out.add(
        AlertInfo(
          id: id.toInt(),
          kind: kind,
          detail: e['detail'] as String?,
          createdAt: createdAt,
          readAt: parseServerTime(e['readAt']),
        ),
      );
    }
    return out;
  }

  /// Đánh dấu một cảnh báo đã đọc (gọi lại không sao). Cảnh báo của máy đã hủy ghép → 404.
  Future<void> markAlertRead(int alertId) =>
      _send('POST', '/api/alerts/$alertId/read', null, auth: _Auth.parent);

  /// App của máy con theo trạng thái duyệt (`new` = vừa cài, chờ mẹ), mới nhất trước, tối đa 200.
  Future<List<InstalledAppInfo>> getDeviceApps(
    int deviceId, {
    String? status,
  }) async {
    final query = status == null ? '' : '?status=$status';
    final list = await _send(
      'GET',
      '/api/devices/$deviceId/apps$query',
      null,
      auth: _Auth.parent,
    ) as List<dynamic>;
    return [
      for (final e in list.cast<Map<String, dynamic>>())
        InstalledAppInfo(
          id: (e['id'] as num).toInt(),
          packageName: e['packageName'] as String,
          label: e['label'] as String? ?? e['packageName'] as String,
          status: e['status'] as String,
          firstSeenAt: parseServerTime(e['firstSeenAt']),
          decidedAt: parseServerTime(e['decidedAt']),
        ),
    ];
  }

  /// Báo cáo sử dụng của máy con từ [from] đến [to] (gồm cả hai đầu, tối đa 90 ngày), cũ nhất trước. Ngày máy con
  /// chưa báo thì không có trong kết quả. Dòng hỏng bị bỏ qua.
  Future<List<UsageDayInfo>> getDeviceUsage(
    int deviceId, {
    required DateTime from,
    required DateTime to,
  }) async {
    String ymd(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    final list = await _send(
      'GET',
      '/api/devices/$deviceId/usage?from=${ymd(from)}&to=${ymd(to)}',
      null,
      auth: _Auth.parent,
    ) as List<dynamic>;
    final out = <UsageDayInfo>[];
    for (final e in list) {
      try {
        final m = e as Map<String, dynamic>;
        final p = (m['date'] as String).split('-').map(int.parse).toList();
        out.add(
          UsageDayInfo(
            date: DateTime(p[0], p[1], p[2]),
            totalMinutes: (m['totalMinutes'] as num).toInt(),
            blocks: (m['blocks'] as num?)?.toInt() ?? 0,
            apps: {
              for (final a in ((m['apps'] as Map?) ?? const {}).entries)
                a.key as String: (a.value as num).toInt(),
            },
          ),
        );
      } catch (_) {
        // Dòng hỏng: bỏ qua, không làm hỏng cả báo cáo.
      }
    }
    return out;
  }

  /// Mẹ cho phép / chặn một app mới của máy con; máy con áp ở lượt đồng bộ kế (tối đa vài phút).
  /// Nơi gọi phải qua `ParentGate` trước.
  Future<void> setDeviceAppStatus(
    int deviceId,
    String packageName, {
    required bool allow,
  }) => _send(
    'PUT',
    '/api/devices/$deviceId/apps/${Uri.encodeComponent(packageName)}',
    {'status': allow ? AppStatus.allowed : AppStatus.blocked},
    auth: _Auth.parent,
  );

  static int? _requestMinutes(Object? payload) {
    if (payload is! String) return null;
    try {
      final m = jsonDecode(payload);
      return m is Map<String, dynamic> ? (m['minutes'] as num?)?.toInt() : null;
    } catch (_) {
      return null;
    }
  }

  // ---- Vị trí và hàng rào địa lý (mẹ) ----

  /// Mẹ đang cho máy con chia sẻ vị trí không (API-11). Mặc định của server là bật.
  Future<bool> getLocationSharing(int deviceId) async {
    final m = await _send(
      'GET',
      '/api/devices/$deviceId/location-sharing',
      null,
      auth: _Auth.parent,
    );
    return m is Map<String, dynamic> ? m['enabled'] != false : true;
  }

  /// Bật/tắt chia sẻ vị trí; máy con áp ở lượt đồng bộ kế (tối đa vài phút). Chỉ đổi cờ, không xóa lịch sử.
  /// Nơi gọi phải qua `ParentGate` trước.
  Future<bool> setLocationSharing(int deviceId, bool enabled) async {
    final m = await _send(
      'PUT',
      '/api/devices/$deviceId/location-sharing',
      {'enabled': enabled},
      auth: _Auth.parent,
    );
    return m is Map<String, dynamic> ? m['enabled'] == true : enabled;
  }

  /// Xóa toàn bộ lịch sử vị trí của máy con trên server. Nơi gọi phải qua `ParentGate` + hộp xác nhận.
  Future<void> deleteLocationHistory(int deviceId) => _send(
    'DELETE',
    '/api/devices/$deviceId/locations',
    null,
    auth: _Auth.parent,
  );

  /// Vị trí mới nhất; `null` nếu máy con chưa gửi lần nào. Mẹ đã tắt chia sẻ → [ApiException.isForbidden].
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
      for (final g
          in (m['geofences'] as List<dynamic>).cast<Map<String, dynamic>>())
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

  /// Máy con xem tên máy, tên gia đình, phiên bản luật (API-01).
  Future<DeviceSelfInfo> fetchMyInfo() async {
    final m = await _send('GET', '/api/devices/me', null, auth: _Auth.device)
        as Map<String, dynamic>;
    return DeviceSelfInfo(
      m['name'] as String,
      m['familyName'] as String,
      m['policyVersion'] as int,
    );
  }

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
