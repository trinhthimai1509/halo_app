import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Semantic color tokens, exposed through [ThemeData.extensions].
///
/// Only a light palette exists in this phase; a dark one is a second
/// constant instance plus a dark [ThemeData].
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.hairline,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accent,
    required this.accentSecondary,
    required this.onAccent,
    required this.userBubble,
    required this.danger,
    required this.dangerSurface,
    required this.ambientPrimary,
    required this.ambientSecondary,
    required this.shadow,
  });

  static const AppPalette light = AppPalette(
    background: AppColors.ivory,
    surface: AppColors.white,
    surfaceMuted: AppColors.mist,
    hairline: AppColors.hairline,
    textPrimary: AppColors.ink,
    textSecondary: AppColors.slate,
    textTertiary: AppColors.fog,
    accent: AppColors.periwinkle,
    accentSecondary: AppColors.lavender,
    onAccent: AppColors.white,
    userBubble: AppColors.bubble,
    danger: AppColors.coral,
    dangerSurface: AppColors.coralTint,
    ambientPrimary: AppColors.skyTint,
    ambientSecondary: AppColors.lavenderTint,
    shadow: AppColors.ink,
  );

  final Color background;
  final Color surface;
  final Color surfaceMuted;
  final Color hairline;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color accent;
  final Color accentSecondary;
  final Color onAccent;
  final Color userBubble;
  final Color danger;
  final Color dangerSurface;
  final Color ambientPrimary;
  final Color ambientSecondary;
  final Color shadow;

  /// The signature blue → lavender gradient used for primary actions.
  LinearGradient get accentGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [accent, accentSecondary],
      );

  @override
  AppPalette copyWith({
    Color? background,
    Color? surface,
    Color? surfaceMuted,
    Color? hairline,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? accent,
    Color? accentSecondary,
    Color? onAccent,
    Color? userBubble,
    Color? danger,
    Color? dangerSurface,
    Color? ambientPrimary,
    Color? ambientSecondary,
    Color? shadow,
  }) {
    return AppPalette(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      hairline: hairline ?? this.hairline,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      accent: accent ?? this.accent,
      accentSecondary: accentSecondary ?? this.accentSecondary,
      onAccent: onAccent ?? this.onAccent,
      userBubble: userBubble ?? this.userBubble,
      danger: danger ?? this.danger,
      dangerSurface: dangerSurface ?? this.dangerSurface,
      ambientPrimary: ambientPrimary ?? this.ambientPrimary,
      ambientSecondary: ambientSecondary ?? this.ambientSecondary,
      shadow: shadow ?? this.shadow,
    );
  }

  @override
  AppPalette lerp(AppPalette? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      background: mix(background, other.background),
      surface: mix(surface, other.surface),
      surfaceMuted: mix(surfaceMuted, other.surfaceMuted),
      hairline: mix(hairline, other.hairline),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
      textTertiary: mix(textTertiary, other.textTertiary),
      accent: mix(accent, other.accent),
      accentSecondary: mix(accentSecondary, other.accentSecondary),
      onAccent: mix(onAccent, other.onAccent),
      userBubble: mix(userBubble, other.userBubble),
      danger: mix(danger, other.danger),
      dangerSurface: mix(dangerSurface, other.dangerSurface),
      ambientPrimary: mix(ambientPrimary, other.ambientPrimary),
      ambientSecondary: mix(ambientSecondary, other.ambientSecondary),
      shadow: mix(shadow, other.shadow),
    );
  }
}
