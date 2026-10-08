import 'package:flutter/material.dart';

import '../../app/theme/app_palette.dart';

extension ThemeContext on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;

  TextTheme get textStyles => Theme.of(this).textTheme;

  /// True when the user asked the OS to reduce motion. Decorative looping
  /// animations stop and transitions become instant or cross-fades.
  bool get reduceMotion => MediaQuery.disableAnimationsOf(this);
}
