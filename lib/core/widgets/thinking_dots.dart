import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/app_durations.dart';
import '../../app/theme/app_spacing.dart';
import '../extensions/context_extensions.dart';

/// Three softly bouncing dots — the lightweight "generating" indicator.
class ThinkingDots extends StatefulWidget {
  const ThinkingDots({super.key, this.color, this.semanticLabel});

  final Color? color;
  final String? semanticLabel;

  @override
  State<ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<ThinkingDots>
    with SingleTickerProviderStateMixin {
  static const int _dotCount = 3;
  static const double _phaseStep = 0.18;
  static const double _lift = 3;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppDurations.thinkingDots,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.reduceMotion) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? context.palette.textSecondary;
    final reduceMotion = context.reduceMotion;
    return Semantics(
      label: widget.semanticLabel,
      liveRegion: widget.semanticLabel != null,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < _dotCount; i++)
              _Dot(
                color: color,
                wave: reduceMotion ? 0.5 : _wave(i),
              ),
          ],
        ),
      ),
    );
  }

  double _wave(int index) {
    final phase = (_controller.value - index * _phaseStep) % 1;
    // A bump over the first half of the cycle, rest over the second half.
    return phase < 0.5 ? math.sin(phase * 2 * math.pi) : 0;
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.wave});

  final Color color;
  final double wave;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
      child: Transform.translate(
        offset: Offset(0, -_ThinkingDotsState._lift * wave),
        child: Container(
          width: AppSizes.thinkingDot,
          height: AppSizes.thinkingDot,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.35 + 0.65 * wave),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
