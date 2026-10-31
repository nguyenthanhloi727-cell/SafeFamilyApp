import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../security/ui/parent_gate.dart';
import 'api_client.dart';
import 'connection_session.dart';
import 'policy_schema.dart';

enum PolicyPushResult {
  /// Không phải máy mẹ, hoặc chưa chọn máy con: không làm gì.
  skipped,

  /// Server đã có đúng luật này.
  pushed,

  /// Luật trên server đã đổi ở nơi khác và mẹ chọn giữ bản trên server.
  keptServer,

  /// Mất mạng / server lỗi / quá lớn. Luật trên máy mẹ vẫn đã lưu.
  failed,
}

/// Máy mẹ đẩy luật (giới hạn thời gian + khóa ứng dụng) của máy này lên máy con
/// đã chọn. Gọi [changed] sau mỗi lần mẹ lưu luật cục bộ: gom các lần sửa dồn
/// dập trong [debounce] rồi gửi một lần.
///
/// Khóa phụ huynh: việc *sửa* luật đã nằm sau `ParentAreaGuard` / `ParentGate`
/// của từng màn, nên gửi tự động không hỏi lại. Riêng *ghi đè* luật mà nơi khác
/// vừa đổi thì hỏi mẹ và đòi `ParentGate.always` trước khi ghi.
///
/// Lệch phiên bản (409) → tải luật server về, so với luật máy này; nếu khác thì
/// hỏi mẹ, không bao giờ ghi đè im lặng.
class PolicySync {
  PolicySync({
    required this.api,
    required this.session,
    required this.navigatorKey,
    required this.loadTimeLimit,
    required this.blockedPackages,
    this.debounce = const Duration(seconds: 2),
  });

  final ApiClient api;
  final ConnectionSession session;
  final GlobalKey<NavigatorState> navigatorKey;

  /// `TimeLimitConfig.toJson()` của máy này.
  final Future<String> Function() loadTimeLimit;

  /// Các app đang khóa trên máy này.
  final Set<String> Function() blockedPackages;
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

  /// Luật cục bộ vừa đổi.
  void changed() {
    if (_disposed || !active) return;
    _timer?.cancel();
    _timer = Timer(debounce, _drain);
  }

  /// Gửi ngay (nút "Gửi luật" thủ công). Trả về kết quả; đã báo mẹ bằng thanh thông báo.
  Future<PolicyPushResult> pushNow() async {
    _timer?.cancel();
    return _push();
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
      final json = PolicySchema.build(
        timeLimit: jsonDecode(await loadTimeLimit()) as Map<String, dynamic>,
        blocked: blockedPackages(),
      );
      if (utf8.encode(json).length > PolicySchema.maxBytes) {
        _say('Luật quá lớn, không gửi được lên máy con.');
        return PolicyPushResult.failed;
      }
      final known = session.policyVersionOf(id);
      if (known != null) {
        try {
          return await _put(id, json, known);
        } on ApiException catch (e) {
          if (!e.isConflict) rethrow;
        }
      }
      // Chưa biết phiên bản, hoặc 409: tải luật server về rồi mới quyết.
      final current = await api.getPolicy(id);
      if (current.version == 0) return await _put(id, json, 0);
      if (PolicySchema.sameContent(current.json, json)) {
        await session.setPolicyVersion(id, current.version);
        _say('Máy con đã có đúng luật này.');
        return PolicyPushResult.pushed;
      }
      return await _askOverwrite(id, json, current);
    } on ApiException catch (e) {
      _say('Chưa gửi được luật lên máy con: ${e.message}');
      return PolicyPushResult.failed;
    } on FormatException {
      _say('Luật trên máy này bị lỗi định dạng, chưa gửi.');
      return PolicyPushResult.failed;
    }
  }

  Future<PolicyPushResult> _put(int id, String json, int expected) async {
    final saved = await api.putPolicy(id, json, expected);
    await session.setPolicyVersion(id, saved.version);
    _say('Đã gửi luật cho máy con (phiên bản ${saved.version}).');
    return PolicyPushResult.pushed;
  }

  Future<PolicyPushResult> _askOverwrite(
    int id,
    String json,
    PolicyInfo current,
  ) async {
    final context = navigatorKey.currentState?.overlay?.context;
    if (context == null || !context.mounted) return PolicyPushResult.failed;
    final overwrite = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Luật trên máy con đã đổi ở nơi khác'),
        content: Text(
          'Máy chủ đang giữ luật phiên bản ${current.version}, khác với luật '
          'trên máy này. Ghi đè bằng luật trên máy này, hay giữ luật đang có '
          'trên máy chủ?',
        ),
        actions: [
          TextButton(
            key: const Key('policy-keep-server'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Giữ luật trên máy chủ'),
          ),
          FilledButton(
            key: const Key('policy-overwrite'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Ghi đè'),
          ),
        ],
      ),
    );
    if (overwrite != true) {
      // Nhớ phiên bản đã thấy: lần sửa sau của mẹ mới là ý định mới.
      await session.setPolicyVersion(id, current.version);
      _say('Giữ luật trên máy chủ. Luật trên máy này chưa được gửi.');
      return PolicyPushResult.keptServer;
    }
    if (!context.mounted ||
        !await ParentGate.always(context, 'Ghi đè luật của máy con')) {
      _say('Chưa ghi đè. Luật trên máy chủ giữ nguyên.');
      return PolicyPushResult.keptServer;
    }
    return _put(id, json, current.version);
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

  /// Báo luật cục bộ vừa đổi (không làm gì nếu không có scope).
  static void notifyChanged(BuildContext context) =>
      maybeOf(context)?.changed();

  @override
  bool updateShouldNotify(PolicySyncScope oldWidget) => sync != oldWidget.sync;
}
