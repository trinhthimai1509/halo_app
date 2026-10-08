import 'dart:async';

import '../../../../core/error/app_exception.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/conversation_summary.dart';
import '../../domain/repositories/chat_repository.dart';
import '../datasources/chat_local_data_source.dart';

/// [ChatRepository] backed by the local SQLite database.
///
/// Adds what the raw data source lacks: change notification for
/// [watchConversations] and translation of database errors into
/// [StorageException].
class LocalChatRepository implements ChatRepository {
  LocalChatRepository(this._source);

  final ChatLocalDataSource _source;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  @override
  Stream<List<ConversationSummary>> watchConversations() {
    late final StreamController<List<ConversationSummary>> controller;
    StreamSubscription<void>? changes;

    Future<void> emit() async {
      try {
        final summaries = await _source.fetchSummaries();
        if (!controller.isClosed) controller.add(summaries);
      } catch (error, stackTrace) {
        if (!controller.isClosed) {
          controller.addError(
            StorageException('Could not load conversations.', error),
            stackTrace,
          );
        }
      }
    }

    controller = StreamController<List<ConversationSummary>>(
      onListen: () {
        // Subscribe before the first query so no change can be missed.
        changes = _changes.stream.listen((_) => emit());
        emit();
      },
      onCancel: () => changes?.cancel(),
    );
    return controller.stream;
  }

  @override
  Future<Conversation?> getConversation(String id) =>
      _guard('load the conversation', () => _source.fetchConversation(id));

  @override
  Future<List<ChatMessage>> getMessages(String conversationId) =>
      _guard('load messages', () => _source.fetchMessages(conversationId));

  @override
  Future<void> createConversation(Conversation conversation) => _mutate(
        'create the conversation',
        () => _source.insertConversation(conversation),
      );

  @override
  Future<void> addMessage(ChatMessage message) =>
      _mutate('save the message', () => _source.insertMessage(message));

  @override
  Future<void> deleteConversation(String id) =>
      _mutate('delete the conversation', () => _source.deleteConversation(id));

  Future<void> dispose() => _changes.close();

  Future<void> _mutate(String action, Future<void> Function() body) async {
    await _guard(action, body);
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<T> _guard<T>(String action, Future<T> Function() body) async {
    try {
      return await body();
    } on AppException {
      rethrow;
    } catch (error) {
      throw StorageException('Could not $action.', error);
    }
  }
}
