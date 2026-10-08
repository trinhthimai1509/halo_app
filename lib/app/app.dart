import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/constants/app_strings.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

class OfflineAiChatApp extends StatelessWidget {
  const OfflineAiChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      // Dark mode: add `darkTheme: AppTheme.dark()` once a dark AppPalette
      // exists.
      themeMode: ThemeMode.light,
      initialRoute: AppRoutes.chat,
      onGenerateRoute: AppRouter.onGenerateRoute,
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: AppTheme.lightSystemOverlay,
        child: child!,
      ),
    );
  }
}
