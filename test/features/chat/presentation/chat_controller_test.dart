import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_ai_chat/features/chat/domain/entities/message_role.dart';
import 'package:offline_ai_chat/features/chat/presentation/state/chat_controller.dart';
import 'package:offline_ai_chat/features/chat/presentation/state/chat_state.dart';
import 'package:offline_ai_chat/features/chat/presentation/state/conversation_list_controller.dart';
import 'package:offline_ai_chat/features/local_ai/data/fake_local_ai_service.dart';
import 'package:offline_ai_chat/features/local_ai/data/fake_responses.dart';
import 'package:offline_ai_chat/features/local_ai/domain/local_ai_service.dart';

import '../../../helpers/in_memory_chat_repository.dart';
import '../../../helpers/test_overrides.dart';

void main() {
  late InMemoryChatRepository repository;

  setUp(() => repository = InMemoryChatRepository());

  ProviderContainer createContainer({FakeLocalAiService? ai}) =>
      ProviderContainer.test(
        overrides: testOverrides(repository: repository, ai: ai),
      );

  group('sending a text message', () {
    test('creates a conversation, stores both turns and streams the reply',
        () async {
      final container = createContainer();
      final history = <ChatState>[];
      container.listen(chatControllerProvider, (_, next) => history.add(next));

      await container
          .read(chatControllerProvider.notifier)
          .send('  Explain something  ');

      final state = container.read(chatControllerProvider);
      expect(state.status, GenerationStatus.idle);
      expect(state.streamingReply, isNull);
      expect(state.conversation?.title, 'Explain something');
      expect(state.messages.map((m) => m.role),
          [MessageRole.user, MessageRole.assistant]);
      expect(state.messages.first.content, 'Explain something');
      expect(
        state.messages.last.content,
        FakeResponses.replyTo(const [
          AiMessage(role: AiRole.user, content: 'Explain something'),
        ]),
      );

      // Went through thinking → streaming with partial content.
      expect(history.map((s) => s.status), contains(GenerationStatus.thinking));
      final partials = history
          .where((s) => s.status == GenerationStatus.streaming)
          .map((s) => s.streamingReply!.content.length)
          .toList();
      expect(partials.length, greaterThan(1));
      expect(partials, orderedEquals([...partials]..sort()));

      // Persisted.
      final id = state.conversation!.id;
      expect(repository.messages[id], state.messages);
    });

    test('continues the same conversation on the next message', () async {
      final container = createContainer();
      final controller = container.read(chatControllerProvider.notifier);

      await controller.send('First');
      final id = container.read(chatControllerProvider).conversation!.id;
      await controller.send('Second');

      final state = container.read(chatControllerProvider);
      expect(state.conversation!.id, id);
      expect(state.messages, hasLength(4));
      expect(repository.conversations, hasLength(1));
    });

    test('ignores blank input', () async {
      final container = createContainer();

      await container.read(chatControllerProvider.notifier).send('   \n ');

      expect(container.read(chatControllerProvider).isEmpty, isTrue);
      expect(repository.conversations, isEmpty);
    });

    test('stopping keeps and persists the partial reply', () async {
      final container = createContainer(
        ai: FakeLocalAiService(
          initializationDelay: Duration.zero,
          firstChunkDelay: Duration.zero,
          chunkDelay: const Duration(milliseconds: 20),
        ),
      );
      final controller = container.read(chatControllerProvider.notifier);
      final streaming = Completer<void>();
      container.listen(chatControllerProvider, (_, next) {
        if (next.status == GenerationStatus.streaming && !streaming.isCompleted) {
          streaming.complete();
        }
      });

      unawaited(controller.send('Give me ideas'));
      await streaming.future;
      await controller.stopGeneration();

      final state = container.read(chatControllerProvider);
      expect(state.isGenerating, isFalse);
      expect(state.messages, hasLength(2));
      final partial = state.messages.last;
      expect(partial.content, isNotEmpty);
      expect(
        partial.content.length,
        lessThan(FakeResponses.replyTo(const [
          AiMessage(role: AiRole.user, content: 'give me ideas'),
        ]).length),
      );
      expect(repository.messages[state.conversation!.id]!.last, partial);
    });
  });

  group('conversation state', () {
    test('opens a stored conversation and starts a new one', () async {
      final seeded = seedConversation(
        repository,
        id: 'c1',
        title: 'Trip',
        at: testNow,
        question: 'Plan a trip',
        answer: 'Sure',
      );
      final container = createContainer();
      final controller = container.read(chatControllerProvider.notifier);

      await controller.openConversation(seeded.id);
      var state = container.read(chatControllerProvider);
      expect(state.conversation, seeded);
      expect(state.messages.map((m) => m.content), ['Plan a trip', 'Sure']);
      expect(state.isEmpty, isFalse);

      await controller.startNewConversation();
      state = container.read(chatControllerProvider);
      expect(state.conversation, isNull);
      expect(state.isEmpty, isTrue);
    });

    test('opening a missing conversation reports an error', () async {
      final container = createContainer();

      await container
          .read(chatControllerProvider.notifier)
          .openConversation('missing');

      final state = container.read(chatControllerProvider);
      expect(state.error, ChatError.loadFailed);
      expect(state.isEmpty, isTrue);
    });

    test('deleting the open conversation resets the chat', () async {
      seedConversation(repository, id: 'c1', title: 'Trip', at: testNow);
      final container = createContainer();
      container.listen(conversationListProvider, (_, _) {});
      await container.read(chatControllerProvider.notifier).openConversation('c1');
      await container.read(conversationListProvider.future);

      await container.read(conversationListProvider.notifier).delete('c1');

      expect(container.read(chatControllerProvider).conversation, isNull);
      expect(container.read(conversationListProvider).value, isEmpty);
      expect(repository.conversations, isEmpty);
    });
  });
}
