import 'package:sqflite/sqflite.dart';

import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/conversation_summary.dart';
import '../models/conversation_record.dart';
import '../models/message_record.dart';
import 'chat_database.dart';

/// SQL queries for chat data. Knows sqflite; knows nothing about streams,
/// error mapping or the UI.
class ChatLocalDataSource {
  ChatLocalDataSource(this._database);

  final ChatDatabase _database;

  Database get _db => _database.db;

  static const String _conversations = ChatDatabase.conversationsTable;
  static const String _messages = ChatDatabase.messagesTable;

  Future<List<ConversationSummary>> fetchSummaries() async {
    final rows = await _db.rawQuery('''
      SELECT c.*,
        (SELECT m.content FROM $_messages m
          WHERE m.conversation_id = c.id
          ORDER BY m.created_at DESC, m.rowid DESC
          LIMIT 1) AS ${ConversationRecord.lastMessage}
      FROM $_conversations c
      ORDER BY c.updated_at DESC
    ''');
    return rows.map(ConversationRecord.summaryFromRow).toList(growable: false);
  }

  Future<Conversation?> fetchConversation(String id) async {
    final rows = await _db.query(
      _conversations,
      where: '${ConversationRecord.id} = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : ConversationRecord.fromRow(rows.first);
  }

  Future<List<ChatMessage>> fetchMessages(String conversationId) async {
    final rows = await _db.query(
      _messages,
      where: '${MessageRecord.conversationId} = ?',
      whereArgs: [conversationId],
      orderBy: '${MessageRecord.createdAt} ASC, rowid ASC',
    );
    return rows.map(MessageRecord.fromRow).toList(growable: false);
  }

  Future<void> insertConversation(Conversation conversation) {
    return _db.insert(_conversations, ConversationRecord.toRow(conversation));
  }

  Future<void> insertMessage(ChatMessage message) {
    return _db.transaction((txn) async {
      await txn.insert(
        _messages,
        MessageRecord.toRow(message),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.update(
        _conversations,
        {ConversationRecord.updatedAt: message.createdAt.microsecondsSinceEpoch},
        where: '${ConversationRecord.id} = ?',
        whereArgs: [message.conversationId],
      );
    });
  }

  /// Messages are removed by `ON DELETE CASCADE`.
  Future<void> deleteConversation(String id) {
    return _db.delete(
      _conversations,
      where: '${ConversationRecord.id} = ?',
      whereArgs: [id],
    );
  }
}
