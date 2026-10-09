import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/di/providers.dart';
import 'app/third_party_licenses.dart';
import 'features/chat/data/datasources/chat_database.dart';
import 'features/model_setup/data/model_catalog.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerThirdPartyLicenses();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  final database = await ChatDatabase.open();
  final container = ProviderContainer(
    overrides: [chatDatabaseProvider.overrideWithValue(database)],
  );
  // Finish or roll back a model import interrupted by a kill or crash.
  try {
    await container.read(modelInstallerProvider).recover(ModelCatalog.all);
  } catch (_) {
    // Never block start-up; Model Setup shows any remaining problem.
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const OfflineAiChatApp(),
    ),
  );
}
