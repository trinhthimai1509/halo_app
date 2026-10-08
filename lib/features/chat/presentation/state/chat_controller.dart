import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/providers.dart';
import '../../../../core/error/app_exception.dart';
import '../../domain/usecases/send_message.dart';
import 'chat_state.dart';

final chatControllerProvider =
    NotifierProvider<ChatController, ChatState>(ChatController.new);

/// Owns the active conversation: opening, sending, streaming and stopping.
///
/// Business rules live in [SendMessage]; this class only maps its events to
/// UI state and manages the generation subscription.
class ChatController extends Notifier<ChatState> {
  StreamSubscription<SendMessageEvent>? _generation;
  Completer<void>? _generationDone;
  int _openRequest = 0;

  @override
  ChatState build() {
    ref.onDispose(() => _generation?.cancel());
    return const ChatState();
  }

  /// Sends [text] in the current conversation (creating one if needed).
  /// The returned future completes when the reply finishes, fails or is
  /// stopped.
  Future<void> send(String text) {
    final prompt = text.trim();
    if (prompt.isEmpty || state.isGenerating || state.isLoading) {
      return Future.value();
    }

    state = state.copyWith(
      status: GenerationStatus.thinking,
      error: () => null,
    );
    final done = _generationDone = Completer<void>();
    _generation = ref
        .read(sendMessageProvider)
        .call(
          text: prompt,
          conversation: state.conversation,
          history: state.messages,
        )
        .listen(
          _onEvent,
          onError: _onGenerationError,
          onDone: _finishGeneration,
          cancelOnError: true,
        );
    return done.future;
  }

  /// Stops generation and keeps whatever text was already streamed.
  Future<void> stopGeneration() async {
    final subscription = _generation;
    if (subscription == null) return;
    _generation = null;
    await subscription.cancel();
    if (!ref.mounted) return;
    _settleStreamingReply();
    _finishGeneration();
  }

  /// Clears the screen for a fresh conversation.
  Future<void> startNewConversation() async {
    await stopGeneration();
    _openRequest++;
    state = const ChatState();
  }

  Future<void> openConversation(String id) async {
    if (state.conversation?.id == id && !state.isLoading) return;
    await stopGeneration();
    final request = ++_openRequest;
    state = const ChatState(isLoading: true);

    final repository = ref.read(chatRepositoryProvider);
    try {
      final conversation = await repository.getConversation(id);
      final messages = conversation == null
          ? null
          : await repository.getMessages(conversation.id);
      if (!ref.mounted || request != _openRequest) return;
      state = conversation == null
          ? const ChatState(error: ChatError.loadFailed)
          : ChatState(conversation: conversation, messages: messages!);
    } catch (_) {
      if (!ref.mounted || request != _openRequest) return;
      state = const ChatState(error: ChatError.loadFailed);
    }
  }

  /// Called before a conversation is deleted, so an in-flight reply is not
  /// written into a conversation that no longer exists.
  Future<void> closeIfActive(String conversationId) async {
    if (state.conversation?.id == conversationId) {
      await startNewConversation();
    }
  }

  void clearError() {
    if (state.error != null) state = state.copyWith(error: () => null);
  }

  void _onEvent(SendMessageEvent event) {
    switch (event) {
      case UserMessageSaved(:final conversation, :final message):
        state = state.copyWith(
          conversation: () => conversation,
          messages: [...state.messages, message],
        );
      case ReplyStarted(:final draft):
        state = state.copyWith(streamingReply: () => draft);
      case ReplyChunk(:final delta):
        final draft = state.streamingReply;
        if (draft == null) return;
        state = state.copyWith(
          streamingReply: () => draft.copyWith(content: draft.content + delta),
          status: GenerationStatus.streaming,
        );
      case ReplyCompleted(:final message):
        state = state.copyWith(
          messages: [...state.messages, message],
          streamingReply: () => null,
          status: GenerationStatus.idle,
        );
    }
  }

  void _onGenerationError(Object error, StackTrace stackTrace) {
    _generation = null;
    if (!ref.mounted) return;
    _settleStreamingReply();
    state = state.copyWith(
      error: () => error is ModelUnavailableException
          ? ChatError.modelUnavailable
          : ChatError.generationFailed,
    );
    _finishGeneration();
  }

  /// Moves a partial reply (already persisted by [SendMessage]) into the
  /// message list and returns to idle.
  void _settleStreamingReply() {
    final partial = state.streamingReply;
    state = state.copyWith(
      messages: partial != null && partial.content.isNotEmpty
          ? [...state.messages, partial]
          : state.messages,
      streamingReply: () => null,
      status: GenerationStatus.idle,
    );
  }

  void _finishGeneration() {
    _generation = null;
    final done = _generationDone;
    _generationDone = null;
    if (done != null && !done.isCompleted) done.complete();
  }
}
