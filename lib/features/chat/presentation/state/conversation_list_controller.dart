import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/providers.dart';
import '../../domain/entities/conversation_summary.dart';
import 'chat_controller.dart';

final conversationListProvider =
    StreamNotifierProvider<ConversationListController, List<ConversationSummary>>(
  ConversationListController.new,
);

/// Local history, kept in sync with the repository.
class ConversationListController
    extends StreamNotifier<List<ConversationSummary>> {
  @override
  Stream<List<ConversationSummary>> build() =>
      ref.watch(chatRepositoryProvider).watchConversations();

  /// Removes the item immediately (so swipe-to-dismiss never shows a stale
  /// row), then deletes it from storage. Restores the list if deletion
  /// fails and rethrows.
  Future<void> delete(String id) async {
    final previous = state.value;
    if (previous != null) {
      state = AsyncData(
        previous.where((summary) => summary.id != id).toList(growable: false),
      );
    }
    await ref.read(chatControllerProvider.notifier).closeIfActive(id);
    try {
      await ref.read(chatRepositoryProvider).deleteConversation(id);
    } catch (_) {
      if (ref.mounted && previous != null) state = AsyncData(previous);
      rethrow;
    }
  }
}

/// Search text on the history screen; reset when the screen closes.
final historyQueryProvider =
    NotifierProvider.autoDispose<HistoryQueryController, String>(
  HistoryQueryController.new,
);

class HistoryQueryController extends Notifier<String> {
  @override
  String build() => '';

  void update(String query) => state = query;
}

/// History filtered by [historyQueryProvider] (title or last message).
final filteredConversationsProvider =
    Provider.autoDispose<AsyncValue<List<ConversationSummary>>>((ref) {
  final query = ref.watch(historyQueryProvider).trim().toLowerCase();
  final conversations = ref.watch(conversationListProvider);
  if (query.isEmpty) return conversations;
  return conversations.whenData(
    (items) => items
        .where(
          (summary) =>
              summary.conversation.title.toLowerCase().contains(query) ||
              (summary.lastMessagePreview?.toLowerCase().contains(query) ??
                  false),
        )
        .toList(growable: false),
  );
});
