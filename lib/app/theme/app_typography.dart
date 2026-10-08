import 'package:flutter/material.dart';

import 'app_palette.dart';

/// Type scale. No font family is set on purpose: the platform typeface is
/// used (SF Pro on iOS, Roboto on Android), which keeps the app offline and
/// native-feeling on both platforms.
abstract final class AppTypography {
  static TextTheme textTheme(AppPalette palette) {
    return TextTheme(
      // Welcome title on the empty chat screen.
      displaySmall: TextStyle(
        fontSize: 30,
        height: 1.2,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.6,
        color: palette.textPrimary,
      ),
      // Screen titles ("History").
      titleLarge: TextStyle(
        fontSize: 20,
        height: 1.25,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        color: palette.textPrimary,
      ),
      // Header identity, empty-state headings.
      titleMedium: TextStyle(
        fontSize: 17,
        height: 1.3,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: palette.textPrimary,
      ),
      // Conversation titles in history.
      titleSmall: TextStyle(
        fontSize: 15.5,
        height: 1.3,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        color: palette.textPrimary,
      ),
      // Message content and composer input.
      bodyLarge: TextStyle(
        fontSize: 16,
        height: 1.55,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.1,
        color: palette.textPrimary,
      ),
      bodyMedium: TextStyle(
        fontSize: 15,
        height: 1.45,
        fontWeight: FontWeight.w400,
        color: palette.textSecondary,
      ),
      // Message previews.
      bodySmall: TextStyle(
        fontSize: 13.5,
        height: 1.35,
        fontWeight: FontWeight.w400,
        color: palette.textSecondary,
      ),
      // Chips and text buttons.
      labelLarge: TextStyle(
        fontSize: 14.5,
        height: 1.2,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.1,
        color: palette.textPrimary,
      ),
      // Timestamps, captions.
      labelMedium: TextStyle(
        fontSize: 12.5,
        height: 1.2,
        fontWeight: FontWeight.w500,
        color: palette.textSecondary,
      ),
      labelSmall: TextStyle(
        fontSize: 11.5,
        height: 1.2,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.2,
        color: palette.textSecondary,
      ),
    );
  }
}
