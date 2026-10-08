import 'package:flutter/material.dart';

import '../../app/theme/app_spacing.dart';
import '../extensions/context_extensions.dart';

/// Circular icon button with a translucent surface, used in headers and the
/// composer. Built on [IconButton] for focus, tooltip and semantics support.
class SoftIconButton extends StatelessWidget {
  const SoftIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.filled = true,
    this.size = AppSizes.iconButton,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// Whether to draw the translucent circular surface behind the icon.
  final bool filled;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, size: AppSizes.icon),
      style: IconButton.styleFrom(
        fixedSize: Size.square(size),
        minimumSize: const Size.square(AppSizes.minTouchTarget),
        foregroundColor: palette.textPrimary,
        disabledForegroundColor: palette.textTertiary,
        backgroundColor:
            filled ? palette.surface.withValues(alpha: 0.72) : null,
        side: filled
            ? BorderSide(color: palette.hairline.withValues(alpha: 0.7))
            : null,
      ),
    );
  }
}
