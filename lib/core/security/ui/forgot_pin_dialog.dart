import 'package:flutter/material.dart';

import '../parent_guard.dart';
import 'recovery_reset_page.dart';

/// Quên PIN: có mã khôi phục thì đặt lại PIN không mất dữ liệu; chưa có thì
/// chỉ còn cách xóa dữ liệu app. Không có câu hỏi bảo mật — con dễ đoán.
Future<void> showForgotPinDialog(BuildContext context) {
  final guard = ParentGuardScope.read(context);
  final canRecover = guard?.hasRecoveryCode ?? false;
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Quên mã PIN?'),
      content: Text(
        canRecover
            ? 'Nhập mã khôi phục 10 ký tự phụ huynh đã ghi lại lúc thiết lập '
                  'để đặt mã PIN mới. Danh bạ, ảnh và cài đặt được giữ nguyên.\n\n'
                  'Mất cả mã khôi phục thì chỉ còn cách xóa dữ liệu app '
                  '(Cài đặt của máy → Ứng dụng → SafeFamily → Bộ nhớ → Xóa dữ '
                  'liệu), việc này xóa luôn danh bạ gia đình, ảnh và cài đặt.'
            : 'Để bảo vệ con, SafeFamily không có câu hỏi bảo mật.\n\n'
                  'Cách duy nhất: Cài đặt của máy → Ứng dụng → SafeFamily → Bộ '
                  'nhớ → Xóa dữ liệu. Việc này xóa luôn danh bạ gia đình, ảnh '
                  'đã tải và mọi cài đặt; mở lại app để đặt mã PIN mới.',
      ),
      actions: [
        if (canRecover)
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => RecoveryResetPage(guard: guard!),
                ),
              );
            },
            child: const Text('Nhập mã khôi phục'),
          ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(canRecover ? 'Đóng' : 'Đã hiểu'),
        ),
      ],
    ),
  );
}
