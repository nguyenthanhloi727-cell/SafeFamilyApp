import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';
import '../parent_guard.dart';
import 'parent_gate.dart';

/// S19 — Dải "Đang ở chế độ trẻ em" ở đầu màn hình, có nút Thoát (cần xác thực).
class ChildModeBanner extends StatelessWidget {
  const ChildModeBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.secondaryContainer,
      child: SafeArea(
        bottom: false,
        child: Semantics(
          container: true,
          liveRegion: true,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.lg,
              AppSpace.xs,
              AppSpace.xs,
              AppSpace.xs,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.child_care_rounded,
                  color: scheme.onSecondaryContainer,
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Text(
                    'Đang ở chế độ trẻ em',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final guard = ParentGuardScope.read(context);
                    await guard?.setChildMode(
                      false,
                      promptPin: ParentGate.promptFor(context),
                    );
                  },
                  child: const Text('Thoát'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
