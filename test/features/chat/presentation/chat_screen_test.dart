import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_ai_chat/app/app.dart';
import 'package:offline_ai_chat/core/constants/app_strings.dart';

import '../../../helpers/in_memory_chat_repository.dart';
import '../../../helpers/test_overrides.dart';

void main() {
  late InMemoryChatRepository repository;

  setUp(() => repository = InMemoryChatRepository());

  Future<void> pumpApp(WidgetTester tester) async {
    // Reduce Motion stops the looping orb/dots so pumpAndSettle can settle,
    // and exercises the accessibility path.
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await tester.pumpWidget(
      ProviderScope(
        overrides: testOverrides(repository: repository),
        child: const OfflineAiChatApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the welcome state with suggestions', (tester) async {
    await pumpApp(tester);

    expect(find.text(AppStrings.welcomeTitle), findsOneWidget);
    expect(find.text('Give me ideas'), findsOneWidget);
    expect(find.text(AppStrings.composerHint), findsOneWidget);
    expect(find.byTooltip(AppStrings.newChat), findsOneWidget);
  });

  testWidgets('a suggestion sends its prompt and streams the reply',
      (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Give me ideas'));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.welcomeTitle), findsNothing);
    expect(find.text('Give me a few ideas for a relaxing weekend.'),
        findsOneWidget);
    expect(find.textContaining('slow, restful weekend'), findsOneWidget);
    expect(repository.conversations, hasLength(1));
    expect(repository.messages.values.single, hasLength(2));
  });

  testWidgets('typed text is sent and the field is cleared', (tester) async {
    await pumpApp(tester);

    final sendButton = find.bySemanticsLabel(AppStrings.send);
    // Disabled while empty.
    await tester.tap(sendButton, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(repository.conversations, isEmpty);

    await tester.enterText(find.byType(TextField), 'Hello there');
    await tester.pump();
    await tester.tap(sendButton);
    await tester.pumpAndSettle();

    expect(find.text('Hello there'), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, isEmpty);
    expect(repository.messages.values.single.first.content, 'Hello there');
  });

  testWidgets('voice input records, transcribes and fills the composer',
      (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byTooltip(AppStrings.voiceInput));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.listening), findsOneWidget);

    await tester.tap(find.bySemanticsLabel(AppStrings.finishRecording));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.listening), findsNothing);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, isNotEmpty);
  });

  testWidgets('cancelling voice input returns to the text composer',
      (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byTooltip(AppStrings.voiceInput));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel(AppStrings.cancelRecording));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.listening), findsNothing);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, isEmpty);
  });

  testWidgets('fits a small phone with large text without overflow',
      (tester) async {
    tester.view
      ..physicalSize = const Size(320, 568)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await pumpApp(tester);
    // The welcome area scrolls when it does not fit.
    await tester.ensureVisible(find.text('Explain something'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Explain something'));
    await tester.pumpAndSettle();

    // (The prompt itself has scrolled out of view behind the long reply.)
    expect(repository.messages.values.single.first.content,
        'Explain how on-device AI works, in simple terms.');
    expect(find.textContaining('runs directly on your phone'), findsOneWidget);

    // A long multi-line draft grows the composer up to its cap.
    await tester.enterText(
      find.byType(TextField),
      List.filled(12, 'A fairly long line of text').join('\n'),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
