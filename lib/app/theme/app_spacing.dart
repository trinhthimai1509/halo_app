/// 4-pt spacing scale plus layout constants.
abstract final class AppSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 48;

  /// Horizontal page gutter.
  static const double gutter = 20;

  /// Content is centred and capped at this width on tablets / landscape.
  static const double maxContentWidth = 720;
}

/// Fixed component sizes.
abstract final class AppSizes {
  /// Minimum interactive size (Apple HIG 44pt; Material 48dp is met by the
  /// padding around most buttons).
  static const double minTouchTarget = 44;
  static const double iconButton = 44;
  static const double sendButton = 38;
  static const double icon = 22;
  static const double iconSmall = 18;

  static const double orbHero = 88;
  static const double orbVoice = 64;
  static const double orbEmptyHistory = 56;
  static const double orbAvatar = 22;
  static const double orbHeader = 20;

  static const double thinkingDot = 6;
  static const int composerMaxLines = 6;

  /// User bubbles never exceed this fraction of the available width.
  static const double userBubbleWidthFactor = 0.82;
}
