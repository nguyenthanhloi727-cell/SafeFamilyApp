import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';
import '../../widgets/status_banner.dart';
import '../recovery_code.dart';
import 'secure_screen_scope.dart';

/// Hiện mã khôi phục PIN đúng một lần. Phụ huynh phải tích "đã ghi lại" mới
/// bấm tiếp được; không có nút sao chép để mã không nằm lại trong bộ nhớ tạm.
class RecoveryCodeView extends StatefulWidget {
  const RecoveryCodeView({
    super.key,
    required this.code,
    required this.onConfirmed,
    this.confirmLabel = 'Tiếp tục',
  });

  final String code;
  final VoidCallback onConfirmed;
  final String confirmLabel;

  @override
  State<RecoveryCodeView> createState() => _RecoveryCodeViewState();
}

class _RecoveryCodeViewState extends State<RecoveryCodeView> {
  bool _written = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SecureScreenScope(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.key_rounded,
            size: AppSize.avatarLg,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: AppSpace.md),
          Text(
            'Mã khôi phục PIN',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            'Quên mã PIN thì nhập mã này để đặt PIN mới mà không mất dữ liệu. '
            'Mã chỉ hiện lần này, hãy chép ra giấy và cất ở nơi con không thấy.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: AppSpace.lg),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.xl),
              child: SelectionContainer.disabled(
                child: Text(
                  formatRecoveryCode(widget.code),
                  key: const Key('recovery-code'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    letterSpacing: 4,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpace.md),
          const StatusBanner(
            type: StatusType.warning,
            title: 'Ai có mã này đều đặt lại được PIN',
            message: 'Đừng chụp màn hình hay gửi qua tin nhắn.',
          ),
          const SizedBox(height: AppSpace.md),
          CheckboxListTile(
            key: const Key('recovery-written'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _written,
            onChanged: (value) => setState(() => _written = value ?? false),
            title: const Text('Tôi đã ghi lại mã này'),
          ),
          const SizedBox(height: AppSpace.sm),
          FilledButton(
            onPressed: _written ? widget.onConfirmed : null,
            child: Text(widget.confirmLabel),
          ),
        ],
      ),
    );
  }
}
