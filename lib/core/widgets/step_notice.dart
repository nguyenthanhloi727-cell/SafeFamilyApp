import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Banner giữ chỗ: cho biết màn này sẽ làm ở bước nào của kế hoạch.
class StepNotice extends StatelessWidget {
  const StepNotice(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(Icons.construction_rounded, color: scheme.onPrimaryContainer),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: scheme.onPrimaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}
