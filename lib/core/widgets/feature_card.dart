import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import 'coming_soon_badge.dart';

/// Thẻ tính năng: icon + tiêu đề + mô tả, tuỳ chọn nhãn "Sắp có" — DESIGN.md C4.
class FeatureCard extends StatelessWidget {
  const FeatureCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.comingSoon = false,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool comingSoon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Row(
            children: [
              CircleAvatar(
                radius: AppSize.avatarMd / 2,
                backgroundColor: scheme.primaryContainer,
                foregroundColor: scheme.onPrimaryContainer,
                child: Icon(icon, size: AppSize.iconLg),
              ),
              const SizedBox(width: AppSpace.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: AppSpace.sm,
                      runSpacing: AppSpace.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(title, style: theme.textTheme.titleMedium),
                        if (comingSoon) const ComingSoonBadge(),
                      ],
                    ),
                    const SizedBox(height: AppSpace.xs),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
