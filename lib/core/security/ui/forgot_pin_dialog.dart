import 'package:flutter/material.dart';

/// Giải thích giới hạn "quên PIN" (không có câu hỏi bảo mật — con dễ đoán).
Future<void> showForgotPinDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Quên mã PIN?'),
      content: const Text(
        'Để bảo vệ con, SafeFamily không có câu hỏi bảo mật hay cách lấy lại '
        'mã PIN.\n\n'
        'Cách duy nhất: Cài đặt của máy → Ứng dụng → SafeFamily → Bộ nhớ → '
        'Xóa dữ liệu. Việc này xóa luôn danh bạ gia đình, ảnh đã tải và mọi '
        'cài đặt; mở lại app để đặt mã PIN mới.',
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Đã hiểu'),
        ),
      ],
    ),
  );
}
