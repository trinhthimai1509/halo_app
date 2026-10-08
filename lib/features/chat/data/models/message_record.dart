import '../../domain/entities/chat_message.dart';
import '../../domain/entities/message_role.dart';

/// Row mapping for the `messages` table.
abstract final class MessageRecord {
  static const String id = 'id';
  static const String conversationId = 'conversation_id';
  static const String role = 'role';
  static const String content = 'content';
  static const String createdAt = 'created_at';

  static Map<String, Object?> toRow(ChatMessage message) => {
        id: message.id,
        conversationId: message.conversationId,
        role: message.role.name,
        content: message.content,
        createdAt: message.createdAt.microsecondsSinceEpoch,
      };

  static ChatMessage fromRow(Map<String, Object?> row) => ChatMessage(
        id: row[id]! as String,
        conversationId: row[conversationId]! as String,
        role: MessageRole.values.byName(row[role]! as String),
        content: row[content]! as String,
        createdAt: DateTime.fromMicrosecondsSinceEpoch(row[createdAt]! as int),
      );
}
