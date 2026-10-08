import 'package:flutter/material.dart';

import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/extensions/context_extensions.dart';

/// The user's message: a quiet, filled, right-aligned bubble.
class UserMessageBubble extends StatelessWidget {
  const UserMessageBubble({super.key, required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: AlignmentDirectional.centerEnd,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: constraints.maxWidth * AppSizes.userBubbleWidthFactor,
          ),
          child: Semantics(
            label: AppStrings.youSaid,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: palette.userBubble,
                borderRadius: AppRadius.userBubble,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md - AppSpacing.xxs,
                ),
                child: Text(content, style: context.textStyles.bodyLarge),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
