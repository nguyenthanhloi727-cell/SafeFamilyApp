import 'package:flutter/material.dart';

import '../../../core/constants/app_languages.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_snack_bar.dart';
import '../../../core/widgets/step_notice.dart';

/// S05 — Báo thức (trạng thái chờ): chip ngôn ngữ + nút micro lớn (giữ chỗ).
class AlarmPage extends StatelessWidget {
  const AlarmPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Báo thức')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpace.lg),
        children: [
          const StepNotice('Đặt báo thức bằng giọng nói: sẽ làm ở bước 5.'),
          const SizedBox(height: AppSpace.xl),
          Center(
            child: Chip(
              avatar: const Icon(Icons.language_rounded),
              label: Text(AppLanguage.defaultVoice.nativeName),
            ),
          ),
          const SizedBox(height: AppSpace.md),
          Text(
            'Hãy nói: “Đặt báo thức 6 giờ 30 sáng”',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpace.xxl),
          Center(
            child: SizedBox.square(
              dimension: AppSize.micButton,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: EdgeInsets.zero,
                ),
                onPressed: () =>
                    showAppSnackBar(context, 'Micro sẽ làm ở bước 5.'),
                child: Icon(
                  Icons.mic_rounded,
                  size: AppSize.iconLg + AppSpace.sm,
                  semanticLabel: 'Bắt đầu nói',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
