import 'package:flutter/material.dart';

import '../../../core/security/parent_guard.dart';
import '../../../core/security/ui/forgot_pin_dialog.dart';
import '../../../core/security/ui/parent_area_guard.dart';
import '../../../core/security/ui/parent_gate.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_snack_bar.dart';
import '../../../core/widgets/status_banner.dart';
import 'change_pin_page.dart';
import 'first_run_setup_page.dart';
import 'unlock_log_page.dart';

/// S15 — Bảo mật & khóa phụ huynh. Mọi thay đổi đều phải xác thực.
class SecuritySettingsPage extends StatelessWidget {
  const SecuritySettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final guard = ParentGuardScope.maybeOf(context)!;
    final theme = Theme.of(context);
    final cap = guard.capability;

    Widget section(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.xl,
        AppSpace.lg,
        AppSpace.sm,
      ),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );

    return ParentAreaGuard(
      child: Scaffold(
        appBar: AppBar(title: const Text('Bảo mật & khóa phụ huynh')),
        body: ListView(
          padding: const EdgeInsets.only(bottom: AppSpace.xl),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.lg,
                AppSpace.lg,
                AppSpace.lg,
                0,
              ),
              child: _CapabilityCard(guard: guard),
            ),
            section('Cách mở khóa'),
            SwitchListTile(
              secondary: const Icon(Icons.fingerprint_rounded),
              title: const Text('Mở khóa bằng vân tay/khuôn mặt'),
              subtitle: Text(
                cap.canAuthenticate
                    ? 'Không được thì vẫn nhập mã PIN.'
                    : 'Máy chưa có vân tay/khuôn mặt dùng được cho app.',
              ),
              value: guard.biometricEnabled && cap.canAuthenticate,
              onChanged: cap.canAuthenticate
                  ? (value) async {
                      final ok = await guard.setBiometricEnabled(
                        value,
                        promptPin: ParentGate.promptFor(context),
                      );
                      if (!ok && value && context.mounted) {
                        showAppSnackBar(context, 'Chưa bật được sinh trắc.');
                      }
                    }
                  : null,
            ),
            ListTile(
              leading: const Icon(Icons.pin_outlined),
              title: const Text('Đổi mã PIN'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () async {
                final navigator = Navigator.of(context);
                if (!await ParentGate.always(context, 'Đổi mã PIN')) return;
                await navigator.push(
                  MaterialPageRoute<void>(
                    builder: (_) => ChangePinPage(guard: guard),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('Hỏi lại sau khi app ở nền'),
              subtitle: Text('${guard.timeoutMinutes} phút'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _pickTimeout(context, guard),
            ),
            ListTile(
              leading: const Icon(Icons.history_rounded),
              title: const Text('Nhật ký mở khóa'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const UnlockLogPage()),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.help_outline_rounded),
              title: const Text('Quên mã PIN?'),
              onTap: () => showForgotPinDialog(context),
            ),
            section('Giới hạn cần biết'),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpace.lg),
              child: StatusBanner(
                type: StatusType.info,
                title: 'Khóa phụ huynh có giới hạn',
                message:
                    '• $biometricOwnershipWarning\n'
                    '• Khuôn mặt tùy máy: nhiều máy chỉ cho dùng khuôn mặt ở màn '
                    'hình khóa, app không gọi được.\n'
                    '• Chỉ khóa các thao tác bên trong SafeFamily, không chặn '
                    'được app khác trên máy.',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickTimeout(BuildContext context, ParentGuard guard) async {
    final prompt = ParentGate.promptFor(context);
    final picked = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Hỏi lại sau khi app ở nền'),
        children: [
          for (final minutes in parentAreaTimeoutChoices)
            ListTile(
              leading: Icon(
                minutes == guard.timeoutMinutes
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
              ),
              title: Text('$minutes phút'),
              onTap: () => Navigator.of(context).pop(minutes),
            ),
        ],
      ),
    );
    if (picked != null) {
      await guard.setTimeoutMinutes(picked, promptPin: prompt);
    }
  }
}

class _CapabilityCard extends StatelessWidget {
  const _CapabilityCard({required this.guard});

  final ParentGuard guard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cap = guard.capability;
    final supported = cap.supportedLabel.isEmpty
        ? 'không có vân tay/khuôn mặt dùng được cho app'
        : cap.supportedLabel;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Máy này hỗ trợ: $supported',
              key: const Key('device-support'),
              style: theme.textTheme.titleMedium,
            ),
            if (cap.hasHardware && !cap.enrolled) ...[
              const SizedBox(height: AppSpace.sm),
              const Text(
                'Chưa đăng ký vân tay/khuôn mặt trong Cài đặt của máy — '
                'đăng ký xong quay lại đây để bật.',
              ),
            ],
            if (!cap.faceHardware) ...[
              const SizedBox(height: AppSpace.sm),
              Text(
                'Khuôn mặt: không dùng được trong app. Nếu máy có "Mở khóa '
                'bằng khuôn mặt", đó là loại Android chỉ cho dùng ở màn hình '
                'khóa (chưa đủ an toàn để app khác gọi).',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
