import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/app_durations.dart';
import '../../app/theme/app_palette.dart';
import '../extensions/context_extensions.dart';

enum AiOrbMode {
  /// Slow breathing and rotation — the assistant is present but idle.
  idle,

  /// Faster rotation and pulse — the assistant is generating.
  thinking,

  /// Expanding rings — the microphone is open.
  listening,
}

/// The assistant's visual identity: a softly glowing gradient sphere.
///
/// Painted in a single [CustomPainter] driven by one repeating controller, so
/// it costs one layer and no widget rebuilds per frame. Stops animating when
/// Reduce Motion is enabled or [animate] is false.
class AiOrb extends StatefulWidget {
  const AiOrb({
    super.key,
    required this.size,
    this.mode = AiOrbMode.idle,
    this.animate = true,
  });

  /// Size of the whole box, including glow. The sphere itself is ~60% of it.
  final double size;
  final AiOrbMode mode;
  final bool animate;

  @override
  State<AiOrb> createState() => _AiOrbState();
}

class _AiOrbState extends State<AiOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _durationFor(widget.mode),
  );

  static Duration _durationFor(AiOrbMode mode) =>
      mode == AiOrbMode.idle ? AppDurations.orbIdle : AppDurations.orbActive;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(AiOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode) {
      _controller.duration = _durationFor(widget.mode);
    }
    _syncAnimation();
  }

  void _syncAnimation() {
    final shouldAnimate = widget.animate && !context.reduceMotion;
    if (shouldAnimate) {
      _controller.repeat();
    } else {
      _controller
        ..stop()
        ..value = 0.15;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.square(widget.size),
          painter: _OrbPainter(
            progress: _controller,
            mode: widget.mode,
            palette: context.palette,
          ),
        ),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter({
    required this.progress,
    required this.mode,
    required this.palette,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final AiOrbMode mode;
  final AppPalette palette;

  static const double _coreFraction = 0.30;
  static const double _tau = math.pi * 2;

  double get _breathAmplitude => switch (mode) {
        AiOrbMode.idle => 0.035,
        AiOrbMode.thinking => 0.07,
        AiOrbMode.listening => 0.05,
      };

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    final center = size.center(Offset.zero);
    final breath = (math.sin(t * _tau) + 1) / 2;
    final coreRadius =
        size.shortestSide * _coreFraction * (1 + _breathAmplitude * breath);

    _paintGlow(canvas, center, coreRadius, breath);
    if (mode == AiOrbMode.listening) _paintRings(canvas, center, coreRadius, t);
    _paintCore(canvas, center, coreRadius, t);
    _paintHighlight(canvas, center, coreRadius);
  }

  void _paintGlow(Canvas canvas, Offset center, double radius, double breath) {
    final glowRadius = radius * (1.55 + 0.15 * breath);
    final rect = Rect.fromCircle(center: center, radius: glowRadius);
    final strength = mode == AiOrbMode.idle ? 0.22 : 0.32;
    canvas.drawCircle(
      center,
      glowRadius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            palette.accent.withValues(alpha: strength),
            palette.accentSecondary.withValues(alpha: strength * 0.5),
            palette.accentSecondary.withValues(alpha: 0),
          ],
          stops: const [0.45, 0.72, 1],
        ).createShader(rect),
    );
  }

  void _paintRings(Canvas canvas, Offset center, double radius, double t) {
    const ringCount = 2;
    for (var i = 0; i < ringCount; i++) {
      final phase = (t * 2 + i / ringCount) % 1;
      canvas.drawCircle(
        center,
        radius * (1 + 0.62 * phase),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = palette.accent.withValues(alpha: 0.35 * (1 - phase)),
      );
    }
  }

  /// A slowly rotating accent → lavender base with a soft pale light
  /// orbiting inside it. (A sweep gradient would show a seam at its centre.)
  void _paintCore(Canvas canvas, Offset center, double radius, double t) {
    final rect = Rect.fromCircle(center: center, radius: radius);
    final angle = t * _tau;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.accentSecondary, palette.accent],
          transform: GradientRotation(angle),
        ).createShader(rect),
    );

    final lightCenter = center +
        Offset(math.cos(angle), math.sin(angle)) * (radius * 0.45);
    final lightRect = Rect.fromCircle(center: lightCenter, radius: radius * 0.85);
    canvas
      ..save()
      ..clipPath(Path()..addOval(rect))
      ..drawCircle(
        lightCenter,
        radius * 0.85,
        Paint()
          ..shader = RadialGradient(
            colors: [
              palette.ambientPrimary.withValues(alpha: 0.9),
              palette.ambientPrimary.withValues(alpha: 0),
            ],
          ).createShader(lightRect),
      )
      ..restore();
  }

  void _paintHighlight(Canvas canvas, Offset center, double radius) {
    final highlightCenter = center.translate(-radius * 0.32, -radius * 0.38);
    final rect = Rect.fromCircle(center: highlightCenter, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            palette.surface.withValues(alpha: 0.85),
            palette.surface.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_OrbPainter oldDelegate) =>
      oldDelegate.mode != mode || oldDelegate.palette != palette;
}
