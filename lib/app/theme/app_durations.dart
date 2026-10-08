import 'package:flutter/animation.dart';

abstract final class AppDurations {
  /// Press feedback.
  static const Duration fast = Duration(milliseconds: 140);

  /// State changes of a single control (send button, focus ring).
  static const Duration medium = Duration(milliseconds: 240);

  /// Larger layout changes (composer mode switch, empty → conversation).
  static const Duration slow = Duration(milliseconds: 380);

  /// Staggered entrance of the welcome screen.
  static const Duration entrance = Duration(milliseconds: 720);

  /// One full cycle of the idle orb.
  static const Duration orbIdle = Duration(milliseconds: 5200);

  /// One full cycle of the active (thinking / listening) orb.
  static const Duration orbActive = Duration(milliseconds: 2000);

  static const Duration thinkingDots = Duration(milliseconds: 1200);
  static const Duration caretBlink = Duration(milliseconds: 900);
}

abstract final class AppCurves {
  static const Curve standard = Curves.easeInOutCubic;
  static const Curve emphasized = Curves.easeOutCubic;
  static const Curve enter = Curves.easeOutQuart;
  static const Curve exit = Curves.easeInCubic;
}
