import 'package:flutter_test/flutter_test.dart';
import 'package:offline_ai_chat/core/utils/id_generator.dart';
import 'package:offline_ai_chat/features/chat/domain/assistant_instructions.dart';
import 'package:offline_ai_chat/features/chat/domain/entities/conversation.dart';
import 'package:offline_ai_chat/features/chat/domain/usecases/send_message.dart';
import 'package:offline_ai_chat/features/local_ai/domain/local_ai_service.dart';

import '../../../helpers/in_memory_chat_repository.dart';
import '../../../helpers/test_overrides.dart';

/// Records the request and replies with a fixed text.
class _RecordingAi implements LocalAiService {
  GenerationRequest? lastRequest;
  int calls = 0;

  @override
  bool get isReady => true;

  @override
  Future<void> initialize() async {}

  @override
  Stream<String> generate(GenerationRequest request) {
    lastRequest = request;
    calls++;
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
    expect(messages.first.content, AssistantInstructions.systemPrompt(testNow));
    expect(messages[1].content, 'Tôi tên là Mai.');
    expect(messages[2].content, 'Tên bạn là Mai.');
    expect(messages.last.content, 'Tên tôi là gì?');
  });

  test('history is sent once per turn, never duplicated, across three turns',
      () async {
    final repository = InMemoryChatRepository();
    final ai = _RecordingAi();
    final sendMessage = SendMessage(
      repository: repository,
      ai: ai,
      ids: IdGenerator(),
      clock: () => testNow,
    );
    final first = await sendMessage(text: 'Một').toList();
    final conversation = (first.first as UserMessageSaved).conversation;
    for (final text in ['Hai', 'Ba']) {
      await sendMessage(
        text: text,
        conversation: conversation,
        history: [...repository.messages[conversation.id]!],
      ).drain<void>();
    }
    final contents = ai.lastRequest!.messages.skip(1).map((m) => m.content);
    expect(contents, [
      'Một', 'Tên bạn là Mai.', 'Hai', 'Tên bạn là Mai.', 'Ba',
    ]);
  });

  test('a plain calendar question is answered from the clock, not the model',
      () async {
    final repository = InMemoryChatRepository();
    final ai = _RecordingAi();
    final sendMessage = SendMessage(
      repository: repository,
      ai: ai,
      ids: IdGenerator(),
      clock: () => DateTime(2026, 10, 8, 22, 5),
    );
    final events = await sendMessage(text: 'Xin chào hôm nay là thứ mấy').toList();
    final reply = (events.last as ReplyCompleted).message;
    expect(reply.content, 'Xin chào! Hôm nay là Thứ Năm, ngày 8 tháng 10 năm 2026.');
    expect(ai.calls, 0);
    expect(repository.messages.values.single.map((m) => m.content), [
      'Xin chào hôm nay là thứ mấy',
      'Xin chào! Hôm nay là Thứ Năm, ngày 8 tháng 10 năm 2026.',
    ]);
  });

  test('regression: the reported October 2026 conversation', () async {
    // Device conversation 2026-10-09 20:13: the model called October a
    // "tháng nhuận" and said it needed the Internet. Turns 1-3 must now be
    // answered in Dart, and those answers must reach the model as history
    // for the corrections that follow (turns 4-5).
    final repository = InMemoryChatRepository();
    final ai = _RecordingAi();
    final sendMessage = SendMessage(
      repository: repository,
      ai: ai,
      ids: IdGenerator(),
      clock: () => DateTime(2026, 10, 9, 20, 13),
    );
    Future<String> send(String text, Conversation conversation) async {
      final events = await sendMessage(
        text: text,
        conversation: conversation,
        history: [...repository.messages[conversation.id]!],
      ).toList();
      return (events.last as ReplyCompleted).message.content;
    }

    final first = await sendMessage(text: 'Xin chào hôm nay là thứ mấy')
        .toList();
    final conversation = (first.first as UserMessageSaved).conversation;
    expect(
      (first.last as ReplyCompleted).message.content,
      'Xin chào! Hôm nay là Thứ Sáu, ngày 9 tháng 10 năm 2026.',
    );
    expect(
      await send('Tháng này có bao nhiêu ngày', conversation),
      'Tháng 10 năm 2026 có 31 ngày (dương lịch).',
    );
    expect(
      await send(
        'Biết là tháng mười mà không biết tháng mười có bao nhiêu '
        'ngày à',
        conversation,
      ),
      'Tháng 10 năm 2026 có 31 ngày (dương lịch).',
    );
    expect(ai.calls, 0);

    await send(
      'Tháng mười làm gì có tháng nhuận với tháng không nhượng trời',
      conversation,
    );
    await send('Tôi không nói lịch âm', conversation);
    expect(ai.calls, 2);

    final sent = ai.lastRequest!.messages;
    expect(sent.first.role, AiRole.system);
    expect(sent.skip(1).map((m) => (m.role, m.content)), [
      (AiRole.user, 'Xin chào hôm nay là thứ mấy'),
      (
        AiRole.assistant,
        'Xin chào! Hôm nay là Thứ Sáu, ngày 9 tháng 10 năm 2026.',
      ),
      (AiRole.user, 'Tháng này có bao nhiêu ngày'),
      (AiRole.assistant, 'Tháng 10 năm 2026 có 31 ngày (dương lịch).'),
      (
        AiRole.user,
        'Biết là tháng mười mà không biết tháng mười có bao nhiêu ngày à',
      ),
      (AiRole.assistant, 'Tháng 10 năm 2026 có 31 ngày (dương lịch).'),
      (
        AiRole.user,
        'Tháng mười làm gì có tháng nhuận với tháng không nhượng trời',
      ),
      (AiRole.assistant, 'Tên bạn là Mai.'),
      (AiRole.user, 'Tôi không nói lịch âm'),
    ]);
    // Persisted, so reopening the conversation keeps the same history.
    expect(repository.messages[conversation.id]!.length, 10);
  });
}
