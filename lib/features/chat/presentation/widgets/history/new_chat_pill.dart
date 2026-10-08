import 'package:flutter/material.dart';

import '../../../../../app/theme/app_radius.dart';
import '../../../../../app/theme/app_shadows.dart';
import '../../../../../app/theme/app_spacing.dart';
import '../../../../../core/constants/app_strings.dart';
import '../../../../../core/extensions/context_extensions.dart';
import '../../../../../core/widgets/pressable_scale.dart';

/// Floating dark pill at the bottom of History.
class NewChatPill extends StatelessWidget {
  const NewChatPill({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Center(
        child: PressableScale(
          onTap: onPressed,
          semanticLabel: AppStrings.newChat,
          child: ExcludeSemantics(
            child: Container(
              constraints:
                  const BoxConstraints(minHeight: AppSizes.minTouchTarget + 4),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
                vertical: AppSpacing.md,
              ),
              decoration: BoxDecoration(
                color: palette.textPrimary,
                borderRadius: AppRadius.pillAll,
                boxShadow: AppShadows.floating(palette.shadow),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.add_rounded,
                    size: AppSizes.icon,
                    color: palette.surface,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    AppStrings.newChat,
                    style: context.textStyles.labelLarge?.copyWith(
                      color: palette.surface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
