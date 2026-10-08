import 'dart:async';

import 'package:offline_ai_chat/features/chat/domain/entities/chat_message.dart';
import 'package:offline_ai_chat/features/chat/domain/entities/conversation.dart';
import 'package:offline_ai_chat/features/chat/domain/entities/conversation_summary.dart';
import 'package:offline_ai_chat/features/chat/domain/repositories/chat_repository.dart';

/// Test double with the same observable behaviour as the SQLite repository.
class InMemoryChatRepository implements ChatRepository {
  final Map<String, Conversation> conversations = {};
  final Map<String, List<ChatMessage>> messages = {};
  final StreamController<void> _changes = StreamController<void>.broadcast();

  void seed(Conversation conversation, List<ChatMessage> history) {
    conversations[conversation.id] = conversation;
    messages[conversation.id] = [...history];
  }

  @override
  Stream<List<ConversationSummary>> watchConversations() {
    late final StreamController<List<ConversationSummary>> controller;
    StreamSubscription<void>? changes;
    controller = StreamController<List<ConversationSummary>>(
      onListen: () {
        changes = _changes.stream.listen((_) => controller.add(_summaries()));
        controller.add(_summaries());
      },
      onCancel: () => changes?.cancel(),
    );
    return controller.stream;
  }

  List<ConversationSummary> _summaries() {
    final sorted = conversations.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return [
      for (final conversation in sorted)
        ConversationSummary(
          conversation: conversation,
          lastMessagePreview: messages[conversation.id]?.lastOrNull?.content,
        ),
    ];
  }

  @override
  Future<Conversation?> getConversation(String id) async => conversations[id];

  @override
  Future<List<ChatMessage>> getMessages(String conversationId) async =>
      [...?messages[conversationId]];

  @override
  Future<void> createConversation(Conversation conversation) async {
    conversations[conversation.id] = conversation;
    messages[conversation.id] = [];
    _changes.add(null);
  }

  @override
  Future<void> addMessage(ChatMessage message) async {
    final conversation = conversations[message.conversationId];
    if (conversation == null) {
      throw StateError('Unknown conversation ${message.conversationId}');
    }
    messages[message.conversationId]!.add(message);
    conversations[message.conversationId] =
        conversation.copyWith(updatedAt: message.createdAt);
    _changes.add(null);
  }

  @override
  Future<void> deleteConversation(String id) async {
    conversations.remove(id);
    messages.remove(id);
    _changes.add(null);
  }
}
