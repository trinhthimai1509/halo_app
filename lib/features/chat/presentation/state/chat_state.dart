import 'package:flutter/foundation.dart';

import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation.dart';

enum GenerationStatus {
  idle,

  /// Waiting for the first token.
  thinking,

  /// Tokens are arriving.
  streaming,
}

enum ChatError { generationFailed, modelUnavailable, loadFailed }

/// State of the conversation currently shown on the chat screen.
@immutable
class ChatState {
  const ChatState({
    this.conversation,
    this.messages = const [],
    this.streamingReply,
    this.status = GenerationStatus.idle,
    this.isLoading = false,
    this.error,
  });

  /// Null until the first message of a new chat is stored.
  final Conversation? conversation;

  /// Completed messages, oldest first.
  final List<ChatMessage> messages;

  /// The assistant reply being generated, growing chunk by chunk.
  final ChatMessage? streamingReply;

  final GenerationStatus status;

  /// A stored conversation is being opened.
  final bool isLoading;

  /// One-shot error to surface; cleared by the controller.
  final ChatError? error;

  bool get isGenerating => status != GenerationStatus.idle;

  /// True when the welcome screen should be shown.
  bool get isEmpty => messages.isEmpty && !isGenerating && !isLoading;

  ChatState copyWith({
    ValueGetter<Conversation?>? conversation,
    List<ChatMessage>? messages,
    ValueGetter<ChatMessage?>? streamingReply,
    GenerationStatus? status,
    bool? isLoading,
    ValueGetter<ChatError?>? error,
  }) {
    return ChatState(
      conversation: conversation != null ? conversation() : this.conversation,
      messages: messages ?? this.messages,
      streamingReply:
          streamingReply != null ? streamingReply() : this.streamingReply,
      status: status ?? this.status,
      isLoading: isLoading ?? this.isLoading,
      error: error != null ? error() : this.error,
    );
  }
}
