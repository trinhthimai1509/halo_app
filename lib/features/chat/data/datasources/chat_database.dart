import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Owns the SQLite connection and schema.
class ChatDatabase {
  ChatDatabase._(this.db);

  static const String fileName = 'offline_ai_chat.db';
  static const int schemaVersion = 1;

  static const String conversationsTable = 'conversations';
  static const String messagesTable = 'messages';

  final Database db;

  /// Opens (and creates on first launch) the database.
  ///
  /// [factory] and [path] exist for tests, which use the FFI factory and a
  /// temporary file.
  static Future<ChatDatabase> open({
    DatabaseFactory? factory,
    String? path,
  }) async {
    final dbFactory = factory ?? databaseFactory;
    final resolvedPath =
        path ?? p.join(await dbFactory.getDatabasesPath(), fileName);
    final db = await dbFactory.openDatabase(
      resolvedPath,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: _createSchema,
      ),
    );
    return ChatDatabase._(db);
  }

  static Future<void> _createSchema(Database db, int version) async {
    final batch = db.batch()
      ..execute('''
        CREATE TABLE $conversationsTable (
          id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )''')
      ..execute('''
        CREATE TABLE $messagesTable (
          id TEXT PRIMARY KEY,
          conversation_id TEXT NOT NULL
            REFERENCES $conversationsTable(id) ON DELETE CASCADE,
          role TEXT NOT NULL,
          content TEXT NOT NULL,
          created_at INTEGER NOT NULL
        )''')
      ..execute(
        'CREATE INDEX idx_messages_conversation '
        'ON $messagesTable(conversation_id, created_at)',
      )
      ..execute(
        'CREATE INDEX idx_conversations_updated '
        'ON $conversationsTable(updated_at DESC)',
      );
    await batch.commit(noResult: true);
  }

  Future<void> close() => db.close();
}
