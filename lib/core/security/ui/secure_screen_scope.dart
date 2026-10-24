import 'package:flutter/widgets.dart';

import '../device_guard.dart';

/// Bọc màn nhạy cảm (nhập PIN, mã khôi phục, phụ huynh): trong lúc màn này hiện,
/// Android chặn chụp/ghi màn hình và ẩn nội dung trong màn hình đa nhiệm.
class SecureScreenScope extends StatefulWidget {
  const SecureScreenScope({super.key, required this.child});

  final Widget child;

  @override
  State<SecureScreenScope> createState() => _SecureScreenScopeState();
}

class _SecureScreenScopeState extends State<SecureScreenScope> {
  @override
  void initState() {
    super.initState();
    SecureScreen.acquire();
  }

  @override
  void dispose() {
    SecureScreen.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
