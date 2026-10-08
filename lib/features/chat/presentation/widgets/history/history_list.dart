import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/di/providers.dart';
import '../../../../../app/theme/app_spacing.dart';
import '../../../../../core/constants/app_strings.dart';
import '../../../domain/entities/conversation_summary.dart';
import '../../state/chat_controller.dart';
import '../../state/conversation_list_controller.dart';
import 'history_tile.dart';

class HistoryList extends ConsumerWidget {
  const HistoryList({super.key, required this.conversations});

  /// Leaves room for the floating "New chat" pill.
  static const double _bottomInset = 112;
  static const double _snackBarBottomMargin = 84;

  final List<ConversationSummary> conversations;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider)();
    final activeId =
        ref.watch(chatControllerProvider.select((s) => s.conversation?.id));
    final bottomPadding =
        MediaQuery.paddingOf(context).bottom + _bottomInset;

    return ListView.separated(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        bottomPadding,
      ),
      itemCount: conversations.length,
      separatorBuilder: (_, _) => const Divider(
        indent: AppSpacing.md,
        endIndent: AppSpacing.md,
      ),
      itemBuilder: (context, index) {
        final summary = conversations[index];
        return HistoryTile(
          key: ValueKey(summary.id),
          summary: summary,
          now: now,
          isActive: summary.id == activeId,
          onOpen: () {
            ref
                .read(chatControllerProvider.notifier)
                .openConversation(summary.id);
            Navigator.of(context).pop();
          },
          onDelete: () => _delete(context, ref, summary.id),
        );
      },
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, String id) async {
    final messenger = ScaffoldMessenger.of(context);
    // Floats above the "New chat" pill instead of covering it.
    SnackBar snackBar(String message) => SnackBar(
          content: Text(message),
          margin: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            _snackBarBottomMargin,
          ),
        );
    try {
      await ref.read(conversationListProvider.notifier).delete(id);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(snackBar(AppStrings.conversationDeleted));
    } catch (_) {
      messenger.showSnackBar(snackBar(AppStrings.deleteFailed));
    }
  }
}
