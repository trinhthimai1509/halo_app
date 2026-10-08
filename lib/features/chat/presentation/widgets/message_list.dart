import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/providers.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/utils/relative_date.dart';
import '../../../../core/widgets/entry_animation.dart';
import '../../domain/entities/chat_message.dart';
import '../state/chat_controller.dart';
import 'assistant_message.dart';
import 'streaming_reply.dart';
import 'user_message_bubble.dart';

/// The conversation, newest at the bottom.
///
/// Uses a reversed list so the view stays pinned to the latest message while
/// a reply streams in and the keyboard opens, without manual scroll
/// management; if the user scrolls up to read, their position is kept.
class MessageList extends ConsumerStatefulWidget {
  const MessageList({super.key});

  @override
  ConsumerState<MessageList> createState() => _MessageListState();
}

class _MessageListState extends ConsumerState<MessageList> {
  static const Duration _timestampGap = Duration(hours: 1);

  /// Ids already on screen; only messages not in here animate in. Seeded
  /// with the messages present when the list is created (an opened
  /// conversation appears instantly).
  late final Set<String> _seen = {
    for (final message in ref.read(chatControllerProvider).messages) message.id,
  };

  @override
  Widget build(BuildContext context) {
    final messages =
        ref.watch(chatControllerProvider.select((state) => state.messages));
    final isGenerating =
        ref.watch(chatControllerProvider.select((state) => state.isGenerating));
    final streamingId = ref.watch(
      chatControllerProvider.select((state) => state.streamingReply?.id),
    );
    // The finished reply replaces the streaming one in place: no re-entry.
    if (streamingId != null) _seen.add(streamingId);

    final replySlot = isGenerating ? 1 : 0;
    final now = ref.watch(clockProvider)();

    return ListView.builder(
      reverse: true,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.lg,
        AppSpacing.gutter,
        AppSpacing.xl,
      ),
      itemCount: messages.length + replySlot,
      // Keeps existing message elements (and their state) when new items
      // are inserted at the bottom.
      findChildIndexCallback: (key) {
        if (key is! ValueKey<String>) return null;
        final position = messages.indexWhere((m) => m.id == key.value);
        return position < 0 ? null : replySlot + messages.length - 1 - position;
      },
      itemBuilder: (context, index) {
        if (index < replySlot) {
          final previous = messages.isEmpty ? null : messages.last;
          return Padding(
            padding: EdgeInsets.only(top: _gapBefore(previous, isUser: false)),
            child: const EntryAnimation(child: StreamingReply()),
          );
        }

        final position = messages.length - 1 - (index - replySlot);
        final message = messages[position];
        final previous = position > 0 ? messages[position - 1] : null;
        final isNew = _seen.add(message.id);

        return Padding(
          key: ValueKey(message.id),
          padding: EdgeInsets.only(top: _gapBefore(previous, isUser: message.isUser)),
          child: EntryAnimation(
            enabled: isNew,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_needsTimestamp(previous, message))
                  _TimestampDivider(time: message.createdAt, now: now),
                if (message.isUser)
                  UserMessageBubble(content: message.content)
                else
                  AssistantMessage(content: message.content),
              ],
            ),
          ),
        );
      },
    );
  }

  static double _gapBefore(ChatMessage? previous, {required bool isUser}) {
    if (previous == null) return 0;
    if (previous.isUser == isUser) return AppSpacing.md;
    return isUser ? AppSpacing.xxxl : AppSpacing.xl;
  }

  static bool _needsTimestamp(ChatMessage? previous, ChatMessage message) =>
      previous == null ||
      message.createdAt.difference(previous.createdAt) >= _timestampGap;
}

class _TimestampDivider extends StatelessWidget {
  const _TimestampDivider({required this.time, required this.now});

  final DateTime time;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final clock = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(time),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Text(
        '${formatRelativeDay(time, now: now)} · $clock',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}
