import 'package:flutter/material.dart';

import '../../app/theme/app_durations.dart';
import '../extensions/context_extensions.dart';

/// Fades and lifts its child into place once, when first built.
///
/// Pass `enabled: false` for content that was already on screen (e.g. an
/// opened conversation) so only genuinely new items animate.
class EntryAnimation extends StatefulWidget {
  const EntryAnimation({
    super.key,
    required this.child,
    this.enabled = true,
    this.offsetY = 12,
    this.duration = AppDurations.slow,
  });

  final Widget child;
  final bool enabled;
  final double offsetY;
  final Duration duration;

  @override
  State<EntryAnimation> createState() => _EntryAnimationState();
}

class _EntryAnimationState extends State<EntryAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: AppCurves.enter,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (widget.enabled && !context.reduceMotion) {
      _controller.forward();
    } else {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, child) => Opacity(
        opacity: _curve.value,
        child: Transform.translate(
          offset: Offset(0, widget.offsetY * (1 - _curve.value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}
