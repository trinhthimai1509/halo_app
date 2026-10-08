import 'package:flutter/material.dart';

import '../../features/chat/presentation/screens/chat_screen.dart';
import '../../features/chat/presentation/screens/history_screen.dart';

abstract final class AppRoutes {
  static const String chat = '/';
  static const String history = '/history';
}

/// Two routes do not justify a routing package. [MaterialPageRoute] picks up
/// the platform transitions from the theme (Cupertino swipe-back on iOS,
/// predictive back on Android).
abstract final class AppRouter {
  static Route<void> onGenerateRoute(RouteSettings settings) {
    final Widget page = switch (settings.name) {
      AppRoutes.history => const HistoryScreen(),
      _ => const ChatScreen(),
    };
    return MaterialPageRoute<void>(settings: settings, builder: (_) => page);
  }
}
