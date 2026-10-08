import 'package:flutter/material.dart';

import '../../../../../app/theme/app_durations.dart';
import '../../../../../app/theme/app_shadows.dart';
import '../../../../../app/theme/app_spacing.dart';
import '../../../../../core/constants/app_strings.dart';
import '../../../../../core/extensions/context_extensions.dart';
import '../../../../../core/widgets/pressable_scale.dart';

enum SendButtonMode { disabled, ready, stop }

/// Circular primary action. Muted when there is nothing to send, gradient
/// when ready, and a stop control while a reply is generating.
class SendButton extends StatelessWidget {
  const SendButton({
    super.key,
    required this.mode,
    required this.onSend,
    required this.onStop,
  });

  static const double _iconSize = 20;

  final SendButtonMode mode;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isStop = mode == SendButtonMode.stop;
    final label = isStop ? AppStrings.stopGenerating : AppStrings.send;
    final onTap = switch (mode) {
      SendButtonMode.disabled => null,
      SendButtonMode.ready => onSend,
      SendButtonMode.stop => onStop,
    };

    return Tooltip(
      message: label,
      child: PressableScale(
        onTap: onTap,
        semanticLabel: label,
        pressedScale: 0.9,
        child: Padding(
          // Visual size 38, touch target 44.
          padding: const EdgeInsets.all(
            (AppSizes.minTouchTarget - AppSizes.sendButton) / 2,
          ),
          child: AnimatedScale(
            scale: mode == SendButtonMode.disabled ? 0.92 : 1,
            duration: AppDurations.medium,
            curve: AppCurves.emphasized,
            child: AnimatedContainer(
              duration: AppDurations.medium,
              curve: AppCurves.standard,
              width: AppSizes.sendButton,
              height: AppSizes.sendButton,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: switch (mode) {
                  SendButtonMode.disabled => palette.surfaceMuted,
                  SendButtonMode.ready => null,
                  SendButtonMode.stop => palette.textPrimary,
                },
                gradient:
                    mode == SendButtonMode.ready ? palette.accentGradient : null,
                boxShadow: mode == SendButtonMode.ready
                    ? AppShadows.accentGlow(palette.accent)
                    : const [],
              ),
              child: AnimatedSwitcher(
                duration: AppDurations.fast,
                transitionBuilder: (child, animation) =>
                    ScaleTransition(scale: animation, child: child),
                child: Icon(
                  isStop ? Icons.stop_rounded : Icons.arrow_upward_rounded,
                  key: ValueKey(isStop),
                  size: _iconSize,
                  color: mode == SendButtonMode.disabled
                      ? palette.textTertiary
                      : palette.onAccent,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
