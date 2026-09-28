import 'package:flutter/material.dart';

import '../parent_guard.dart';
import 'pin_prompt_page.dart';

/// Chỗ gọi duy nhất cho giao diện: mỗi thao tác cần khóa chỉ gọi 1 dòng,
/// không tự viết lại logic. Không có [ParentGuardScope] (test màn lẻ) → cho qua.
abstract final class ParentGate {
  /// Chỉ hỏi khi đang ở chế độ trẻ em (sửa danh bạ, đặt báo thức, ảnh nhóm…).
  static Future<bool> childAction(BuildContext context, String action) =>
      _run(context, (guard, prompt) {
        return guard.requireInChildMode(action, promptPin: prompt);
      });

  /// Vào khu vực phụ huynh (cài đặt, bảo mật, nhật ký, quản lý thiết bị).
  static Future<bool> parentArea(BuildContext context, String action) =>
      _run(context, (guard, prompt) {
        return guard.requireParentArea(action, promptPin: prompt);
      });

  /// Luôn hỏi (đổi PIN, bật/tắt sinh trắc…).
  static Future<bool> always(BuildContext context, String action) => _run(
    context,
    (guard, prompt) => guard.require(action, promptPin: prompt),
  );

  /// Hàm hỏi PIN gắn với [context] (dùng khi gọi thẳng ParentGuard).
  static PinPrompt promptFor(BuildContext context) {
    final navigator = Navigator.of(context);
    return (session) async =>
        await navigator.push<bool>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => PinPromptPage(session: session),
          ),
        ) ??
        false;
  }

  static Future<bool> _run(
    BuildContext context,
    Future<bool> Function(ParentGuard guard, PinPrompt prompt) call,
  ) async {
    final guard = ParentGuardScope.read(context);
    if (guard == null) return true;
    return call(guard, promptFor(context));
  }
}
