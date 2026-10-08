import 'package:flutter/material.dart';

import '../extensions/context_extensions.dart';

/// Off-white canvas with two very faint blue / lavender light sources near
/// the top. Static by design: ambient motion would cost battery for little
/// benefit.
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key, required this.child, this.intensity = 1});

  final Widget child;

  /// Multiplier for the glow opacity (history uses a quieter variant).
  final double intensity;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return ColoredBox(
      color: palette.background,
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final extent = constraints.maxWidth * 1.1;
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        _Glow(
                          color: palette.ambientPrimary,
                          opacity: 0.9 * intensity,
                          diameter: extent,
                          offset: Offset(-extent * 0.35, -extent * 0.45),
                        ),
                        _Glow(
                          color: palette.ambientSecondary,
                          opacity: 0.8 * intensity,
                          diameter: extent,
                          offset: Offset(
                            constraints.maxWidth - extent * 0.6,
                            -extent * 0.35,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({
    required this.color,
    required this.opacity,
    required this.diameter,
    required this.offset,
  });

  final Color color;
  final double opacity;
  final double diameter;
  final Offset offset;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: offset.dx,
      top: offset.dy,
      width: diameter,
      height: diameter,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: opacity.clamp(0, 1)),
              color.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}
