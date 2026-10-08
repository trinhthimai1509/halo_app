import 'package:flutter/widgets.dart';

import '../../app/theme/app_spacing.dart';

/// Centres [child] and caps its width so layouts stay readable on tablets
/// and in landscape without screen-size breakpoints.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
        child: child,
      ),
    );
  }
}
