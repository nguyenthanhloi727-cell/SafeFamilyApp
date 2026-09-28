import 'package:flutter/material.dart';

/// Hiện thông báo ngắn ở cuối màn hình, thay thông báo đang hiện (nếu có).
void showAppSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
