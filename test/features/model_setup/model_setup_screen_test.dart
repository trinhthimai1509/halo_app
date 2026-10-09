import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_ai_chat/app/di/providers.dart';
import 'package:offline_ai_chat/app/theme/app_theme.dart';
import 'package:offline_ai_chat/core/constants/app_strings.dart';
import 'package:offline_ai_chat/features/model_setup/data/model_import_platform.dart';
import 'package:offline_ai_chat/features/model_setup/data/model_installer.dart';
import 'package:offline_ai_chat/features/model_setup/presentation/model_setup_screen.dart';

import 'fake_import_platform.dart';

void main() {
  late Directory root;
  late FakeImportPlatform platform;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('halo_setup_ui_');
    platform = FakeImportPlatform();
  });
  tearDown(() => root.delete(recursive: true));

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          modelInstallerProvider.overrideWithValue(
            ModelInstaller(platform: platform, privateRoot: () async => root.path),
          ),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const ModelSetupScreen()),
      ),
    );
  }

  testWidgets('shows both models as not installed, with storage needs',
      (tester) async {
    await tester.runAsync(() => pump(tester));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();

    expect(find.text(AppStrings.modelSetupTitle), findsOneWidget);
    expect(find.text(AppStrings.modelMissing), findsNWidgets(2));
    expect(find.textContaining('1.3 GB'), findsOneWidget);
    expect(find.textContaining('77 MB'), findsOneWidget);
    expect(find.text(AppStrings.importAction), findsNWidgets(2));
  });

  testWidgets('a wrong file shows a clear error and offers a retry',
      (tester) async {
    platform.nextPick = const [
      PickedDocument(uri: 'content://x', name: 'holiday.jpg', size: 12345),
    ];
    await tester.runAsync(() => pump(tester));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();

    await tester.tap(find.text(AppStrings.importAction).first);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();

    expect(find.text(AppStrings.importWrongLlmFile), findsOneWidget);
    expect(find.text(AppStrings.retryAction), findsOneWidget);
    expect(find.text(AppStrings.modelMissing), findsNWidgets(2));
  });
}
