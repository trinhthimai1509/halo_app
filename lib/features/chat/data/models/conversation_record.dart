import '../../domain/entities/conversation.dart';
import '../../domain/entities/conversation_summary.dart';

/// Row mapping for the `conversations` table.
abstract final class ConversationRecord {
  static const String id = 'id';
  static const String title = 'title';
  static const String createdAt = 'created_at';
  static const String updatedAt = 'updated_at';

  /// Column produced by the summary query.
  static const String lastMessage = 'last_message';

  static Map<String, Object?> toRow(Conversation conversation) => {
        id: conversation.id,
        title: conversation.title,
        createdAt: conversation.createdAt.microsecondsSinceEpoch,
        updatedAt: conversation.updatedAt.microsecondsSinceEpoch,
      };

  static Conversation fromRow(Map<String, Object?> row) => Conversation(
        id: row[id]! as String,
        title: row[title]! as String,
        createdAt: _time(row[createdAt]),
        updatedAt: _time(row[updatedAt]),
      );

  static ConversationSummary summaryFromRow(Map<String, Object?> row) =>
      ConversationSummary(
        conversation: fromRow(row),
        lastMessagePreview: row[lastMessage] as String?,
      );

  static DateTime _time(Object? value) =>
      DateTime.fromMicrosecondsSinceEpoch(value! as int);
}
