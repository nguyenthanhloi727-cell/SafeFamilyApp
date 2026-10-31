import 'package:flutter/material.dart';

import '../../../core/security/parent_guard.dart';
import '../../../core/security/ui/parent_gate.dart';
import '../data/study_approval_platform.dart';

/// Kết quả hộp duyệt giờ học.
enum StudyReview { approved, rejected }

/// Con đã báo "Đã học xong": hỏi phụ huynh duyệt hay từ chối. Duyệt phải xác
/// thực (vân tay hoặc PIN); từ chối chỉ đưa con về học nên không cần.
///
/// Trả `null` nếu con chưa báo xong, phụ huynh đóng hộp hoặc xác thực thất bại
/// (con vẫn ở trạng thái chờ duyệt).
Future<StudyReview?> reviewStudyClaim(
  BuildContext context, {
  required StudyApprovalPlatform platform,
  ParentGuard? guard,
}) async {
  if (await platform.state() != StudyBlockState.childClaimsDone) return null;
  if (!context.mounted) return null;
  final approve = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Con báo đã học xong'),
      content: const Text('Duyệt để con dùng máy lại, hoặc cho con học tiếp.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Học tiếp'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Duyệt'),
        ),
      ],
    ),
  );
  if (approve == null) return null;
  if (!approve) {
    await platform.reject();
    return StudyReview.rejected;
  }
  if (!context.mounted) return null;
  if (guard != null) {
    final ok = await guard.require(
      'Duyệt giờ học: con đã học xong',
      promptPin: ParentGate.promptFor(context),
    );
    if (!ok) return null;
  }
  return await platform.approve() ? StudyReview.approved : null;
}
