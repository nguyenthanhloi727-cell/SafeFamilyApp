import 'package:flutter/material.dart';

import '../../../core/security/parent_guard.dart';
import '../../../core/security/ui/parent_gate.dart';
import '../data/time_limit_platform.dart';

/// Số phút phụ huynh được chọn khi thêm giờ.
const extraTimeChoices = [5, 15, 30];

/// Hộp chọn 5/15/30 phút; `null` nếu hủy.
Future<int?> pickExtraMinutes(BuildContext context) => showDialog<int>(
  context: context,
  builder: (context) => SimpleDialog(
    title: const Text('Thêm giờ cho con'),
    children: [
      for (final minutes in extraTimeChoices)
        SimpleDialogOption(
          onPressed: () => Navigator.of(context).pop(minutes),
          child: Text('Thêm $minutes phút'),
        ),
    ],
  ),
);

/// Chọn số phút → xác thực phụ huynh (vân tay hoặc PIN) → cộng vào hạn mức
/// hôm nay. Chọn trước khi xác thực để nhật ký mở khóa ghi luôn số phút và
/// cách xác thực ("Thêm 15 phút giờ dùng máy · Vân tay · Thành công").
///
/// [guard] `null` (test màn lẻ, chưa đặt khóa) thì bỏ qua xác thực.
/// Trả về số phút đã thêm, hoặc `null` nếu phụ huynh hủy.
Future<int?> grantExtraTime(
  BuildContext context, {
  required TimeLimitPlatform platform,
  ParentGuard? guard,
}) async {
  final minutes = await pickExtraMinutes(context);
  if (minutes == null || !context.mounted) return null;
  final action = 'Thêm $minutes phút giờ dùng máy';
  if (guard != null) {
    final ok = await guard.require(
      action,
      promptPin: ParentGate.promptFor(context),
    );
    if (!ok) return null;
  }
  await platform.addBonus(minutes);
  return minutes;
}
