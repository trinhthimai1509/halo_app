import '../../../../core/error/app_exception.dart';
import '../../../../core/utils/clock.dart';
import '../../../../core/utils/id_generator.dart';
import '../../../local_ai/domain/local_ai_service.dart';
import '../assistant_instructions.dart';
import '../calendar_answers.dart';
import '../entities/chat_message.dart';
import '../entities/conversation.dart';
import '../entities/message_role.dart';
import '../repositories/chat_repository.dart';

/// Progress of one user turn, emitted in order by [SendMessage].
sealed class SendMessageEvent {
  const SendMessageEvent();
}

/// The user's message is stored (in a new conversation if needed).
final class UserMessageSaved extends SendMessageEvent {
  const UserMessageSaved(this.conversation, this.message);
  final Conversation conversation;
  final ChatMessage message;
}

/// The assistant reply has started; [draft] carries its final id.
final class ReplyStarted extends SendMessageEvent {
  const ReplyStarted(this.draft);
  final ChatMessage draft;
}

/// A new piece of reply text.
final class ReplyChunk extends SendMessageEvent {
  const ReplyChunk(this.delta);
  final String delta;
}

/// The full reply was generated and stored.
final class ReplyCompleted extends SendMessageEvent {
  const ReplyCompleted(this.message);
  final ChatMessage message;
}

/// Orchestrates one user turn: persist the prompt, stream the local model's
/// reply (or a calendar answer computed from the device clock), persist the
/// reply.
///
/// Cancelling the returned stream's subscription stops generation; any
/// partial reply that was already shown is still persisted, so history
/// matches what the user saw.
class SendMessage {
  SendMessage({
    required this._repository,
    required this._ai,
    required this._ids,
    required this._clock,
  });

  final ChatRepository _repository;
  final LocalAiService _ai;
  final IdGenerator _ids;
  final Clock _clock;

  /// [conversation] is null for a new chat. [history] is the conversation's
  /// existing messages, oldest first, used as model context.
  Stream<SendMessageEvent> call({
    required String text,
    Conversation? conversation,
    List<ChatMessage> history = const [],
  }) async* {
    final prompt = text.trim();
    if (prompt.isEmpty) throw ArgumentError.value(text, 'text', 'is empty');

    final sentAt = _clock();
    var target = conversation;
    if (target == null) {
      target = Conversation(
        id: _ids.next(),
        title: Conversation.titleFromPrompt(prompt),
        createdAt: sentAt,
        updatedAt: sentAt,
      );
      await _repository.createConversation(target);
    }

    final userMessage = ChatMessage(
      id: _ids.next(),
      conversationId: target.id,
      role: MessageRole.user,
      content: prompt,
      createdAt: sentAt,
    );
    await _repository.addMessage(userMessage);
    target = target.copyWith(updatedAt: sentAt);
    yield UserMessageSaved(target, userMessage);

    // Plain calendar questions are answered from the device clock: the
    // model cannot know today's date and would guess.
    final calendarReply = CalendarAnswers.answer(prompt, sentAt);
    if (calendarReply != null) {
      final reply = ChatMessage(
        id: _ids.next(),
        conversationId: target.id,
        role: MessageRole.assistant,
        content: '',
        createdAt: _clock(),
      );
      yield ReplyStarted(reply);
      yield ReplyChunk(calendarReply);
      final message = reply.copyWith(content: calendarReply);
      await _repository.addMessage(message);
      yield ReplyCompleted(message);
      return;
    }

    if (!_ai.isReady) await _ai.initialize();

    final draft = ChatMessage(
      id: _ids.next(),
      conversationId: target.id,
      role: MessageRole.assistant,
      content: '',
      createdAt: _clock(),
    );
    yield ReplyStarted(draft);

    final reply = StringBuffer();
    var completed = false;
    try {
      // Full history is passed; the AI implementation trims it to its
      // context window.
      final request = GenerationRequest(
        messages: [
          // Built per request so the date/time is current.
          AiMessage(
            role: AiRole.system,
            content: AssistantInstructions.systemPrompt(_clock()),
          ),
          for (final message in [...history, userMessage]) _toAiMessage(message),
        ],
      );
      await for (final delta in _ai.generate(request)) {
        reply.write(delta);
        yield ReplyChunk(delta);
      }
      completed = true;
    } finally {
      // Also runs when the subscriber cancels (user tapped stop) or the
      // model fails mid-stream.
      if (!completed && reply.isNotEmpty) {
        await _repository.addMessage(draft.copyWith(content: reply.toString()));
      }
    }

    if (reply.isEmpty) {
      throw const GenerationException('The model returned an empty reply.');
    }
    final message = draft.copyWith(content: reply.toString());
    await _repository.addMessage(message);
    yield ReplyCompleted(message);
  }

  static AiMessage _toAiMessage(ChatMessage message) => AiMessage(
        role: message.isUser ? AiRole.user : AiRole.assistant,
        content: message.content,
      );
}
