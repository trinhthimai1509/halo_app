import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_ai_chat/features/chat/data/datasources/chat_database.dart';
import 'package:offline_ai_chat/features/chat/data/datasources/chat_local_data_source.dart';
import 'package:offline_ai_chat/features/chat/data/repositories/local_chat_repository.dart';
import 'package:offline_ai_chat/features/chat/domain/entities/chat_message.dart';
import 'package:offline_ai_chat/features/chat/domain/entities/conversation.dart';
import 'package:offline_ai_chat/features/chat/domain/entities/message_role.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Runs against real SQLite (via FFI) and a real database file.
void main() {
  late Directory tempDir;
  late String dbPath;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('offline_ai_chat_test');
    dbPath = p.join(tempDir.path, ChatDatabase.fileName);
  });

  tearDown(() => tempDir.delete(recursive: true));

  Future<(ChatDatabase, LocalChatRepository)> open() async {
    final database =
        await ChatDatabase.open(factory: databaseFactoryFfi, path: dbPath);
    return (database, LocalChatRepository(ChatLocalDataSource(database)));
  }

  final t0 = DateTime(2026, 9, 22, 9);

  Conversation conversation(String id, String title, DateTime at) =>
      Conversation(id: id, title: title, createdAt: at, updatedAt: at);

  ChatMessage message(String id, String conversationId, MessageRole role,
          String content, DateTime at) =>
      ChatMessage(
        id: id,
        conversationId: conversationId,
        role: role,
        content: content,
        createdAt: at,
      );

  test('conversations and messages survive reopening the database', () async {
    var (database, repository) = await open();
    await repository.createConversation(conversation('a', 'Older', t0));
    await repository.addMessage(message('a1', 'a', MessageRole.user, 'Hi', t0));
    await repository.createConversation(
      conversation('b', 'Newer', t0.add(const Duration(minutes: 1))),
    );
    final question = message('b1', 'b', MessageRole.user, 'Question',
        t0.add(const Duration(minutes: 2)));
    // Same timestamp as the question: insertion order must be kept.
    final answer = message('b2', 'b', MessageRole.assistant, 'Answer',
        t0.add(const Duration(minutes: 2)));
    await repository.addMessage(question);
    await repository.addMessage(answer);
    await repository.dispose();
    await database.close();

    (database, repository) = await open();
    addTearDown(database.close);

    final summaries = await repository.watchConversations().first;
    expect(summaries.map((s) => s.conversation.title), ['Newer', 'Older']);
    expect(summaries.first.lastMessagePreview, 'Answer');
    expect(summaries.first.conversation.updatedAt,
        t0.add(const Duration(minutes: 2)));
    expect(await repository.getMessages('b'), [question, answer]);
    expect((await repository.getConversation('a'))?.title, 'Older');
  });

  test('deleting a conversation removes it and all its messages', () async {
    final (database, repository) = await open();
    addTearDown(database.close);
    await repository.createConversation(conversation('a', 'Keep', t0));
    await repository.createConversation(conversation('b', 'Remove', t0));
    await repository.addMessage(message('b1', 'b', MessageRole.user, 'x', t0));
    await repository.addMessage(
        message('b2', 'b', MessageRole.assistant, 'y', t0));

    await repository.deleteConversation('b');

    expect(await repository.getConversation('b'), isNull);
    expect(await repository.getMessages('b'), isEmpty);
    final orphans = await database.db.rawQuery(
      'SELECT COUNT(*) AS n FROM ${ChatDatabase.messagesTable}',
    );
    expect(orphans.single['n'], 0);
    final remaining = await repository.watchConversations().first;
    expect(remaining.map((s) => s.id), ['a']);
  });

  test('watchConversations re-emits after every change', () async {
    final (database, repository) = await open();
    addTearDown(database.close);

    final lengths = <int>[];
    final subscription = repository
        .watchConversations()
        .listen((list) => lengths.add(list.length));
    addTearDown(subscription.cancel);

    Future<void> waitForEmissions(int count) async {
      for (var i = 0; i < 200 && lengths.length < count; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }

    await waitForEmissions(1);
    await repository.createConversation(conversation('a', 'A', t0));
    await waitForEmissions(2);
    await repository.deleteConversation('a');
    await waitForEmissions(3);

    expect(lengths, [0, 1, 0]);
  });
}
