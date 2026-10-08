import '../entities/chat_message.dart';
import '../entities/conversation.dart';
import '../entities/conversation_summary.dart';

/// Persistence contract for conversations and messages.
///
/// Implementations throw `StorageException` on failure.
abstract interface class ChatRepository {
  /// Emits the full history, most recently updated first, and re-emits after
  /// every change made through this repository.
  Stream<List<ConversationSummary>> watchConversations();

  Future<Conversation?> getConversation(String id);

  /// Messages of a conversation, oldest first.
  Future<List<ChatMessage>> getMessages(String conversationId);

  Future<void> createConversation(Conversation conversation);

  /// Stores [message] and moves its conversation's `updatedAt` to the
  /// message time, atomically.
  Future<void> addMessage(ChatMessage message);

  /// Deletes the conversation and all its messages.
  Future<void> deleteConversation(String id);
}
