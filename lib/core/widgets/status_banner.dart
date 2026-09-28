import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';

enum StatusType { info, success, warning, error }

/// C11 — Thông báo trạng thái: icon + tiêu đề + nội dung + nút (tuỳ chọn).
class StatusBanner extends StatelessWidget {
  const StatusBanner({
    super.key,
    required this.type,
    required this.title,
    this.message,
    this.actions = const [],
  });

  final StatusType type;
  final String title;
  final String? message;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final app = theme.extension<AppColors>()!;
    final (Color background, Color foreground, IconData icon) = switch (type) {
      StatusType.info => (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
        Icons.info_outline_rounded,
      ),
      StatusType.success => (
        app.successContainer,
        scheme.onSurface,
        Icons.check_circle_outline_rounded,
      ),
      StatusType.warning => (
        app.warningContainer,
        scheme.onSurface,
        Icons.warning_amber_rounded,
      ),
      StatusType.error => (
        scheme.errorContainer,
        scheme.onErrorContainer,
        Icons.error_outline_rounded,
      ),
    };

    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpace.md),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: foreground),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: foreground,
                    ),
                  ),
                  if (message != null) ...[
                    const SizedBox(height: AppSpace.xs),
                    Text(
                      message!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: foreground,
                      ),
                    ),
                  ],
                  if (actions.isNotEmpty) ...[
                    const SizedBox(height: AppSpace.sm),
                    Wrap(
                      spacing: AppSpace.sm,
                      runSpacing: AppSpace.xs,
                      children: actions,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
