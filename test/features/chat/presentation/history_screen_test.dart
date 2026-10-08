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

  Future<void> pumpHistory(WidgetTester tester) async {
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
    await tester.tap(find.byTooltip(AppStrings.openHistory));
    await tester.pumpAndSettle();
  }

  void seedTwo() {
    seedConversation(
      repository,
      id: 'trip',
      title: 'Planning a weekend trip',
      at: testNow.subtract(const Duration(hours: 1)),
      question: 'Can you suggest a simple itinerary?',
      answer: 'Day one: arrive and explore the old town.',
    );
    seedConversation(
      repository,
      id: 'arch',
      title: 'Flutter architecture',
      at: testNow.subtract(const Duration(days: 1)),
      answer: 'Clean Architecture separates concerns into layers.',
    );
  }

  testWidgets('shows the empty state when there is no history',
      (tester) async {
    await pumpHistory(tester);

    expect(find.text(AppStrings.historyTitle), findsOneWidget);
    expect(find.text(AppStrings.historyEmptyTitle), findsOneWidget);
    expect(find.text(AppStrings.historyEmptyBody), findsOneWidget);
  });

  testWidgets('lists conversations with preview and relative date',
      (tester) async {
    seedTwo();
    await pumpHistory(tester);

    expect(find.text('Planning a weekend trip'), findsOneWidget);
    expect(find.text('Day one: arrive and explore the old town.'),
        findsOneWidget);
    expect(find.text(AppStrings.today), findsOneWidget);
    expect(find.text('Flutter architecture'), findsOneWidget);
    expect(find.text(AppStrings.yesterday), findsOneWidget);

    // Most recent first.
    final tripY = tester.getTopLeft(find.text('Planning a weekend trip')).dy;
    final archY = tester.getTopLeft(find.text('Flutter architecture')).dy;
    expect(tripY, lessThan(archY));
  });

  testWidgets('tapping a conversation reopens it in the chat screen',
      (tester) async {
    seedTwo();
    await pumpHistory(tester);

    await tester.tap(find.text('Flutter architecture'));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.historyTitle), findsNothing);
    expect(find.text('Clean Architecture separates concerns into layers.'),
        findsOneWidget);
  });

  testWidgets('swiping a conversation deletes it', (tester) async {
    seedTwo();
    await pumpHistory(tester);

    await tester.drag(find.text('Planning a weekend trip'), const Offset(-600, 0));
    await tester.pumpAndSettle();

    expect(find.text('Planning a weekend trip'), findsNothing);
    expect(find.text('Flutter architecture'), findsOneWidget);
    expect(repository.conversations.keys, ['arch']);
    expect(find.text(AppStrings.conversationDeleted), findsOneWidget);
  });

  testWidgets('long-press offers delete with confirmation', (tester) async {
    seedTwo();
    await pumpHistory(tester);

    await tester.longPress(find.text('Flutter architecture'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.deleteConversation));
    await tester.pumpAndSettle();

    expect(find.text('Flutter architecture'), findsNothing);
    expect(repository.conversations.keys, ['trip']);
  });

  testWidgets('search filters by title and message text', (tester) async {
    seedTwo();
    await pumpHistory(tester);

    await tester.tap(find.byTooltip(AppStrings.search));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'clean');
    await tester.pumpAndSettle();

    expect(find.text('Flutter architecture'), findsOneWidget);
    expect(find.text('Planning a weekend trip'), findsNothing);
  });
}
