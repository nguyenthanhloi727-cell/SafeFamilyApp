import 'package:flutter/material.dart';

import '../parent_guard.dart';

/// Bọc màn thuộc khu vực phụ huynh (cài đặt, bảo mật, nhật ký, quản lý thiết bị).
/// Phiên phụ huynh hết hạn (app ở nền quá thời gian chờ) → đóng các màn này,
/// muốn vào lại phải xác thực.
class ParentAreaGuard extends StatefulWidget {
  const ParentAreaGuard({super.key, required this.child});

  final Widget child;

  @override
  State<ParentAreaGuard> createState() => _ParentAreaGuardState();
}

class _ParentAreaGuardState extends State<ParentAreaGuard> {
  bool _closing = false;

  @override
  Widget build(BuildContext context) {
    final guard = ParentGuardScope.maybeOf(context);
    if (guard != null && !guard.hasParentSession && !_closing) {
      _closing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      });
    }
    return widget.child;
  }
}
