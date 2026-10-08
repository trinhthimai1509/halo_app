import 'package:flutter/painting.dart';

/// Raw color values of the design system.
///
/// Widgets should not use these directly: read semantic tokens from
/// [AppPalette] (via `context.palette`) so a dark palette can be added later
/// without touching widgets.
abstract final class AppColors {
  static const Color ivory = Color(0xFFF7F6F3);
  static const Color white = Color(0xFFFFFFFF);
  static const Color mist = Color(0xFFF0EFEB);
  static const Color hairline = Color(0xFFE7E5E0);

  static const Color ink = Color(0xFF14161F);
  static const Color slate = Color(0xFF636775);
  static const Color fog = Color(0xFF8E919C);

  static const Color periwinkle = Color(0xFF5B7CFA);
  static const Color lavender = Color(0xFF9B87F5);
  static const Color skyTint = Color(0xFFDCE5FF);
  static const Color lavenderTint = Color(0xFFEBE3FF);
  static const Color bubble = Color(0xFFEBEEF9);

  static const Color coral = Color(0xFFD9434A);
  static const Color coralTint = Color(0xFFFBE9E9);
}
