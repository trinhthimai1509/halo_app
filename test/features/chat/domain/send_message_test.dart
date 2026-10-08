import 'package:flutter_test/flutter_test.dart';
import 'package:offline_ai_chat/core/utils/id_generator.dart';
import 'package:offline_ai_chat/features/chat/domain/assistant_instructions.dart';
import 'package:offline_ai_chat/features/chat/domain/usecases/send_message.dart';
import 'package:offline_ai_chat/features/local_ai/domain/local_ai_service.dart';

import '../../../helpers/in_memory_chat_repository.dart';
import '../../../helpers/test_overrides.dart';

/// Records the request and replies with a fixed text.
class _RecordingAi implements LocalAiService {
  GenerationRequest? lastRequest;

  @override
  bool get isReady => true;

  @override
  Future<void> initialize() async {}

  @override
  Stream<String> generate(GenerationRequest request) {
    lastRequest = request;
    return Stream.fromIterable(['Tên bạn ', 'là Mai.']);
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  test('sends the system prompt, history and the new message in order',
      () async {
    final repository = InMemoryChatRepository();
    final ai = _RecordingAi();
    final sendMessage = SendMessage(
      repository: repository,
      ai: ai,
      ids: IdGenerator(),
      clock: () => testNow,
    );

    final first = await sendMessage(text: 'Tôi tên là Mai.').toList();
    final conversation = (first.first as UserMessageSaved).conversation;
    // A snapshot, as the controller passes; the repository list is live.
    final history = [...repository.messages[conversation.id]!];

    await sendMessage(
      text: 'Tên tôi là gì?',
      conversation: conversation,
      history: history,
    ).drain<void>();

    final messages = ai.lastRequest!.messages;
    expect(messages.map((m) => m.role), [
      AiRole.system,
      AiRole.user,
      AiRole.assistant,
      AiRole.user,
    ]);
    expect(messages.first.content, AssistantInstructions.systemPrompt);
    expect(messages[1].content, 'Tôi tên là Mai.');
    expect(messages[2].content, 'Tên bạn là Mai.');
    expect(messages.last.content, 'Tên tôi là gì?');
  });
}
