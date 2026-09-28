import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Nhãn "Sắp có" — DESIGN.md C10.
class ComingSoonBadge extends StatelessWidget {
  const ComingSoonBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.sm,
        vertical: AppSpace.xxs,
      ),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        'Sắp có',
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: scheme.onSecondaryContainer),
      ),
    );
  }
}
