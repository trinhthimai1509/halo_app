import 'package:flutter_riverpod/misc.dart';
import 'package:offline_ai_chat/app/di/providers.dart';
import 'package:offline_ai_chat/features/chat/domain/entities/chat_message.dart';
import 'package:offline_ai_chat/features/chat/domain/entities/conversation.dart';
import 'package:offline_ai_chat/features/chat/domain/entities/message_role.dart';
import 'package:offline_ai_chat/features/local_ai/data/fake_local_ai_service.dart';
import 'package:offline_ai_chat/features/local_ai/domain/local_ai_service.dart';
import 'package:offline_ai_chat/features/speech/data/fake_speech_to_text_service.dart';

import 'in_memory_chat_repository.dart';

/// Fixed "now" used across tests: Wednesday 23 Sep 2026, 14:30.
final DateTime testNow = DateTime(2026, 9, 23, 14, 30);

FakeLocalAiService instantAi() => FakeLocalAiService(
      initializationDelay: Duration.zero,
      firstChunkDelay: Duration.zero,
      chunkDelay: Duration.zero,
    );

List<Override> testOverrides({
  required InMemoryChatRepository repository,
  LocalAiService? ai,
}) {
  return [
    chatRepositoryProvider.overrideWithValue(repository),
    localAiServiceProvider.overrideWithValue(ai ?? instantAi()),
    speechToTextServiceProvider.overrideWithValue(
      FakeSpeechToTextService(processingDelay: Duration.zero),
    ),
    clockProvider.overrideWithValue(() => testNow),
  ];
}

/// Seeds a conversation with one user message and one reply.
Conversation seedConversation(
  InMemoryChatRepository repository, {
  required String id,
  required String title,
  required DateTime at,
  String question = 'Question',
  String answer = 'Answer',
}) {
  final conversation = Conversation(
    id: id,
    title: title,
    createdAt: at,
    updatedAt: at,
  );
  repository.seed(conversation, [
    ChatMessage(
      id: '$id-q',
      conversationId: id,
      role: MessageRole.user,
      content: question,
      createdAt: at,
    ),
    ChatMessage(
      id: '$id-a',
      conversationId: id,
      role: MessageRole.assistant,
      content: answer,
      createdAt: at,
    ),
  ]);
  return conversation;
}
