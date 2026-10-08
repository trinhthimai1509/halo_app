import 'package:flutter/material.dart';

import '../../../../../app/theme/app_durations.dart';
import '../../../../../app/theme/app_shadows.dart';
import '../../../../../app/theme/app_spacing.dart';
import '../../../../../core/constants/app_strings.dart';
import '../../../../../core/extensions/context_extensions.dart';
import '../../../../../core/widgets/ai_orb.dart';
import '../../../../../core/widgets/pressable_scale.dart';
import '../../state/composer_controller.dart';

/// Voice capture state of the composer:
///
///            Listening…
///   [cancel]  (pulsing orb)  [finish]
class VoiceComposer extends StatelessWidget {
  const VoiceComposer({
    super.key,
    required this.status,
    required this.onCancel,
    required this.onFinish,
  });

  final VoiceStatus status;
  final VoidCallback onCancel;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final isListening = status == VoiceStatus.listening;
    final label = isListening ? AppStrings.listening : AppStrings.transcribing;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          _RoundAction(
            icon: Icons.close_rounded,
            label: AppStrings.cancelRecording,
            visible: isListening,
            onTap: onCancel,
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AiOrb(
                  size: AppSizes.orbVoice,
                  mode: isListening ? AiOrbMode.listening : AiOrbMode.thinking,
                ),
                const SizedBox(height: AppSpacing.xs),
                Semantics(
                  liveRegion: true,
                  child: AnimatedSwitcher(
                    duration: AppDurations.medium,
                    child: Text(
                      label,
                      key: ValueKey(label),
                      style: context.textStyles.labelLarge?.copyWith(
                        color: context.palette.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _RoundAction(
            icon: Icons.check_rounded,
            label: AppStrings.finishRecording,
            visible: isListening,
            onTap: onFinish,
            emphasized: true,
          ),
        ],
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.label,
    required this.visible,
    required this.onTap,
    this.emphasized = false,
  });

  final IconData icon;
  final String label;
  final bool visible;
  final VoidCallback onTap;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: AppDurations.medium,
      child: IgnorePointer(
        ignoring: !visible,
        child: ExcludeSemantics(
          excluding: !visible,
          child: Tooltip(
            message: label,
            child: PressableScale(
              onTap: onTap,
              semanticLabel: label,
              pressedScale: 0.9,
              child: Container(
                width: AppSizes.iconButton,
                height: AppSizes.iconButton,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: emphasized ? null : palette.surfaceMuted,
                  gradient: emphasized ? palette.accentGradient : null,
                  boxShadow:
                      emphasized ? AppShadows.accentGlow(palette.accent) : null,
                ),
                child: Icon(
                  icon,
                  size: AppSizes.icon,
                  color: emphasized ? palette.onAccent : palette.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
