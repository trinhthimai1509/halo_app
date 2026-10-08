import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/di/providers.dart';
import 'app/third_party_licenses.dart';
import 'features/chat/data/datasources/chat_database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerThirdPartyLicenses();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  final database = await ChatDatabase.open();

  runApp(
    ProviderScope(
      overrides: [chatDatabaseProvider.overrideWithValue(database)],
      child: const OfflineAiChatApp(),
    ),
  );
}
