import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';
import '../alarm_controller.dart';

/// C7 — Nút micro lớn: chờ / đang khởi động / đang nghe (có vòng sóng).
class MicButton extends StatelessWidget {
  const MicButton({super.key, required this.state, required this.onPressed});

  final MicState state;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final listening = state == MicState.listening;

    return SizedBox.square(
      dimension: AppSize.micButtonListening,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            width: listening ? AppSize.micButtonListening : AppSize.micButton,
            height: listening ? AppSize.micButtonListening : AppSize.micButton,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: listening ? scheme.primaryContainer : Colors.transparent,
            ),
          ),
          SizedBox.square(
            dimension: AppSize.micButton,
            child: Semantics(
              button: true,
              label: listening ? 'Dừng nghe' : 'Bắt đầu nói giờ báo thức',
              excludeSemantics: true,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: EdgeInsets.zero,
                  elevation: listening ? 6 : 3,
                ),
                onPressed: state == MicState.starting ? null : onPressed,
                child: state == MicState.starting
                    ? const SizedBox.square(
                        dimension: AppSize.iconLg,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      )
                    : Icon(
                        listening ? Icons.stop_rounded : Icons.mic_rounded,
                        size: AppSize.iconLg + AppSpace.sm,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
