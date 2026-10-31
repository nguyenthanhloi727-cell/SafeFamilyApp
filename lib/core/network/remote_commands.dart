import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../widgets/app_snack_bar.dart';
import 'api_client.dart';
import 'api_scope.dart';
import 'connection_session.dart';

/// Gửi lệnh từ xa tới máy con đã chọn (chế độ "mẹ"). Việc xác thực phụ huynh
/// là của nơi gọi (`ParentGate`), hàm ở đây không hỏi lại.
abstract final class RemoteCommands {
  /// Id máy con nếu máy này là mẹ, đã đăng nhập và đã chọn máy con; ngược lại `null`
  /// (nơi gọi làm việc trên chính máy này như cũ).
  static int? targetOf(BuildContext context) {
    final session = ConnectionScope.maybeOf(context);
    if (session == null || ApiScope.maybeOf(context) == null) return null;
    if (session.mode != ConnectionMode.parent || !session.isParentLoggedIn) {
      return null;
    }
    return session.selectedChildId;
  }

  /// Payload `app_unlock_temp` (giới hạn phút kiểm ở server và máy con).
  static String unlockTempPayload(String package, int minutes) =>
      jsonEncode({'package': package, 'minutes': minutes});

  static String packagePayload(String package) =>
      jsonEncode({'package': package});

  static String minutesPayload(int minutes) => jsonEncode({'minutes': minutes});

  /// Gửi một lệnh và báo mẹ bằng thanh thông báo. `true` nếu server nhận.
  static Future<bool> send(
    BuildContext context,
    int childId,
    String type, {
    String? payloadJson,
    required String done,
  }) async {
    final api = ApiScope.maybeOf(context);
    if (api == null) return false;
    try {
      await api.sendCommand(childId, type, payloadJson: payloadJson);
      if (context.mounted) showAppSnackBar(context, done);
      return true;
    } on ApiException catch (e) {
      if (context.mounted) showAppSnackBar(context, e.message);
      return false;
    }
  }
}
