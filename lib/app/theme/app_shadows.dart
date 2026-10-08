import 'package:flutter/painting.dart';

/// Soft, low-opacity elevation. Shadows are tinted with the palette's shadow
/// color so they stay coherent if the palette changes.
abstract final class AppShadows {
  /// Floating surfaces: the composer, the "New chat" pill.
  static List<BoxShadow> floating(Color shadow) => [
        BoxShadow(
          color: shadow.withValues(alpha: 0.07),
          blurRadius: 28,
          offset: const Offset(0, 10),
        ),
        BoxShadow(
          color: shadow.withValues(alpha: 0.04),
          blurRadius: 3,
          offset: const Offset(0, 1),
        ),
      ];

  /// Emphasised floating state (focused composer).
  static List<BoxShadow> floatingRaised(Color shadow) => [
        BoxShadow(
          color: shadow.withValues(alpha: 0.10),
          blurRadius: 36,
          offset: const Offset(0, 14),
        ),
        BoxShadow(
          color: shadow.withValues(alpha: 0.05),
          blurRadius: 4,
          offset: const Offset(0, 1),
        ),
      ];

  /// Barely-there lift for chips.
  static List<BoxShadow> soft(Color shadow) => [
        BoxShadow(
          color: shadow.withValues(alpha: 0.04),
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
      ];

  /// Colored glow under accent buttons.
  static List<BoxShadow> accentGlow(Color accent) => [
        BoxShadow(
          color: accent.withValues(alpha: 0.30),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ];
}
