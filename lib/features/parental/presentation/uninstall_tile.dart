import 'package:flutter/material.dart';

import '../../../core/security/parent_guard.dart';
import '../../../core/security/ui/parent_gate.dart';
import '../../../core/widgets/app_snack_bar.dart';

/// Mục nguy hiểm "Gỡ cài đặt SafeFamily": cảnh báo → PIN → vân tay/Face ID →
/// mở màn gỡ của hệ thống. Sai lớp nào dừng ngay ở lớp đó.
class UninstallTile extends StatelessWidget {
  const UninstallTile({super.key, required this.guard});

  final ParentGuard guard;

  static const _action = 'Gỡ cài đặt SafeFamily';

  @override
  Widget build(BuildContext context) {
    final danger = Theme.of(context).colorScheme.error;
    return ListTile(
      key: const Key('uninstall-tile'),
      leading: Icon(Icons.delete_forever_rounded, color: danger),
      title: Text(_action, style: TextStyle(color: danger)),
      subtitle: const Text('Cần mã PIN rồi vân tay/khuôn mặt.'),
      onTap: () => _run(context),
    );
  }

  Future<void> _run(BuildContext context) async {
    if (!guard.isConfigured) {
      showAppSnackBar(context, 'Chưa đặt mã PIN phụ huynh. Hãy đặt PIN trước.');
      return;
    }
    if (!guard.usesBiometric) {
      showAppSnackBar(
        context,
        'Cần bật mở khóa bằng vân tay/khuôn mặt (mục Cách mở khóa) trước khi gỡ.',
      );
      return;
    }
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(_action),
        content: const Text('Gỡ app sẽ tắt toàn bộ quản lý trên máy này.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Hủy'),
          ),
          TextButton(
            key: const Key('uninstall-continue'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Tiếp tục'),
          ),
        ],
      ),
    );
    if (proceed != true || !context.mounted) return;

    // Lớp 1: PIN (dùng chung đếm sai/khóa của khóa phụ huynh).
    // TODO(verify): khóa hiện là 5 lần sai → 30 giây, tăng dần; yêu cầu gốc là 5 phút.
    final pinOk = await guard.requirePinOnly(
      _action,
      promptPin: ParentGate.promptFor(context),
    );
    if (!pinOk || !context.mounted) return;

    // Lớp 2: sinh trắc, không có nút dùng PIN thay.
    final bioOk = await guard.requireBiometricOnly(_action);
    if (!context.mounted) return;
    if (!bioOk) {
      showAppSnackBar(context, 'Chưa xác thực được vân tay/khuôn mặt.');
      return;
    }

    final started = await guard.device.beginUninstall();
    if (!started && context.mounted) {
      showAppSnackBar(context, 'Máy không mở được màn gỡ ứng dụng.');
    }
  }
}
