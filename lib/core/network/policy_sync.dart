import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../features/profile/data/family_contact.dart';
import 'api_client.dart';
import 'connection_session.dart';
import 'policy_schema.dart';

enum PolicyPushResult {
  /// Không phải máy mẹ, hoặc chưa chọn máy con: không làm gì.
  skipped,

  /// Server đã có đúng số SOS này.
  pushed,

  /// Mất mạng / server lỗi. Số SOS trên máy mẹ vẫn đã lưu.
  failed,
}

/// Máy mẹ sửa LUẬT CỦA MÁY CON trên server. Máy mẹ không giữ luật nào cho chính
/// nó: mỗi lần sửa là đọc luật hiện có của máy con, đổi đúng phần cần đổi
/// (danh sách chặn, giới hạn thời gian, số SOS) rồi ghi lại với số phiên bản đã
/// đọc. Lệch phiên bản (409) thì đọc lại và thử thêm một lần, không ghi đè mù.
class PolicySync {
  PolicySync({
    required this.api,
    required this.session,
    required this.navigatorKey,
    this.loadContacts,
    this.debounce = const Duration(seconds: 2),
  });

  final ApiClient api;
  final ConnectionSession session;
  final GlobalKey<NavigatorState> navigatorKey;

  /// Danh bạ gia đình trên máy mẹ; chỉ các liên hệ đánh dấu khẩn cấp (SOS) được gửi (API-13).
  final Future<List<FamilyContact>> Function()? loadContacts;
  final Duration debounce;

  Timer? _timer;
  bool _running = false;
  bool _again = false;
  bool _disposed = false;

  /// Máy mẹ đã chọn máy con thì có việc để làm.
  bool get active =>
      session.mode == ConnectionMode.parent &&
      session.isParentLoggedIn &&
      session.selectedChildId != null;

  /// Số SOS ở danh bạ máy mẹ vừa đổi: gom các lần sửa dồn dập rồi gửi một lần.
  void changed() {
    if (_disposed || !active) return;
    _timer?.cancel();
    _timer = Timer(debounce, _drain);
  }

  /// Gửi số SOS ngay. Đã báo mẹ bằng thanh thông báo khi lỗi.
  Future<PolicyPushResult> pushNow() async {
    _timer?.cancel();
    return _push();
  }

  /// Các app đang bị chặn trên máy con [id] theo luật trên server.
  /// Chưa có luật → rỗng. Lỗi mạng → [ApiException].
  Future<Set<String>> loadBlocked(int id) async =>
      blockedIn((await api.getPolicy(id)).json);

  /// Danh sách chặn trong chuỗi JSON luật; rỗng nếu thiếu hoặc hỏng.
  static Set<String> blockedIn(String policyJson) {
    try {
      final policy = jsonDecode(policyJson);
      if (policy is! Map) return {};
      final appLock = policy['appLock'];
      final list = appLock is Map ? appLock['blocked'] : null;
      return {if (list is List) ...list.whereType<String>()};
    } catch (_) {
      return {};
    }
  }

  /// `timeLimit` trong chuỗi JSON luật (dạng `TimeLimitConfig.toJson`), `null` nếu chưa có.
  static String? timeLimitIn(String policyJson) {
    try {
      final policy = jsonDecode(policyJson);
      final limit = policy is Map ? policy['timeLimit'] : null;
      return limit is Map ? jsonEncode(limit) : null;
    } catch (_) {
      return null;
    }
  }

  /// Chặn / bỏ chặn một app trên máy con [id]. Trả về danh sách chặn mới;
  /// ném [ApiException] nếu không ghi được.
  Future<Set<String>> setBlocked(int id, String package, bool blocked) async {
    final policy = await _edit(id, (policy) {
      final set = _blockedOf(policy);
      blocked ? set.add(package) : set.remove(package);
      policy['appLock'] = {
        ...?(policy['appLock'] as Map?)?.cast<String, dynamic>(),
        'blocked': set.toList()..sort(),
      };
    });
    return _blockedOf(policy);
  }

  /// Ghi giới hạn thời gian ([timeLimitJson] = `TimeLimitConfig.toJson()`) cho máy con [id].
  Future<void> setTimeLimit(int id, String timeLimitJson) async {
    await _edit(id, (policy) {
      policy['timeLimit'] = jsonDecode(timeLimitJson);
    });
  }

  static Set<String> _blockedOf(Map<String, dynamic> policy) =>
      blockedIn(jsonEncode(policy));

  /// Đọc luật hiện có → [mutate] → ghi lại. Lệch phiên bản thì làm lại một lần.
  Future<Map<String, dynamic>> _edit(
    int id,
    void Function(Map<String, dynamic> policy) mutate,
  ) async {
    ApiException? last;
    for (var attempt = 0; attempt < 2; attempt++) {
      final current = await api.getPolicy(id);
      final policy = current.version == 0
          ? <String, dynamic>{'schemaVersion': PolicySchema.version}
          : Map<String, dynamic>.from(jsonDecode(current.json) as Map);
      mutate(policy);
      try {
        final saved = await api.putPolicy(
          id,
          jsonEncode(policy),
          current.version,
        );
        await session.setPolicyVersion(id, saved.version);
        return policy;
      } on ApiException catch (e) {
        if (!e.isConflict) rethrow;
        last = e;
      }
    }
    throw last!;
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }

  Future<void> _drain() async {
    if (_running) {
      _again = true; // đang gửi: sửa thêm trong lúc đó thì gửi lại sau
      return;
    }
    _running = true;
    try {
      do {
        _again = false;
        await _push();
      } while (_again && !_disposed);
    } finally {
      _running = false;
    }
  }

  Future<PolicyPushResult> _push() async {
    final id = session.selectedChildId;
    if (!active || id == null) return PolicyPushResult.skipped;
    try {
      // Lỗi đọc danh bạ thì ném tiếp để KHÔNG gửi gói thiếu số SOS (máy con sẽ xóa SOS cũ).
      final sos = PolicySchema.sosJson(await loadContacts?.call() ?? const []);
      await _edit(id, (policy) {
        policy['contacts'] = sos;
        if (((policy['schemaVersion'] as num?) ?? 1) < PolicySchema.version) {
          policy['schemaVersion'] = PolicySchema.version;
        }
      });
      _say('Đã gửi số khẩn cấp cho máy con.');
      return PolicyPushResult.pushed;
    } on ApiException catch (e) {
      _say('Chưa gửi được số khẩn cấp lên máy con: ${e.message}');
      return PolicyPushResult.failed;
    } on FormatException {
      _say('Luật của máy con bị lỗi định dạng, chưa gửi.');
      return PolicyPushResult.failed;
    } catch (_) {
      _say('Không đọc được danh bạ khẩn cấp, chưa gửi.');
      return PolicyPushResult.failed;
    }
  }

  void _say(String message) {
    final context = navigatorKey.currentState?.overlay?.context;
    if (context == null || !context.mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Đưa [PolicySync] xuống cây widget. Không có (test màn lẻ) thì không gửi gì.
class PolicySyncScope extends InheritedWidget {
  const PolicySyncScope({super.key, required this.sync, required super.child});

  final PolicySync sync;

  static PolicySync? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PolicySyncScope>()?.sync;

  /// Báo số SOS ở danh bạ máy mẹ vừa đổi (không làm gì nếu không có scope).
  static void notifyChanged(BuildContext context) =>
      maybeOf(context)?.changed();

  @override
  bool updateShouldNotify(PolicySyncScope oldWidget) => sync != oldWidget.sync;
}
