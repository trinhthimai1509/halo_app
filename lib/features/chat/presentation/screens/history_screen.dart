import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_durations.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/ambient_background.dart';
import '../../../../core/widgets/content_width.dart';
import '../state/chat_controller.dart';
import '../state/conversation_list_controller.dart';
import '../widgets/history/history_empty_state.dart';
import '../widgets/history/history_header.dart';
import '../widgets/history/history_list.dart';
import '../widgets/history/new_chat_pill.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  static const double _ambientIntensity = 0.55;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: AmbientBackground(
        intensity: _ambientIntensity,
        child: SafeArea(
          bottom: false,
          child: ContentWidth(
            child: Stack(
              children: [
                const Column(
                  children: [
                    HistoryHeader(),
                    Expanded(child: _HistoryBody()),
                  ],
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: NewChatPill(
                    onPressed: () {
                      ref
                          .read(chatControllerProvider.notifier)
                          .startNewConversation();
                      Navigator.of(context).pop();
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HistoryBody extends ConsumerWidget {
  const _HistoryBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversations = ref.watch(filteredConversationsProvider);
    final isSearching =
        ref.watch(historyQueryProvider.select((q) => q.trim().isNotEmpty));

    final Widget child = switch (conversations) {
      AsyncData(:final value) when value.isEmpty => HistoryEmptyState(
          key: ValueKey('empty-$isSearching'),
          isSearchResult: isSearching,
        ),
      AsyncData(:final value) => HistoryList(
          key: const ValueKey('list'),
          conversations: value,
        ),
      AsyncError() => Center(
          key: const ValueKey('error'),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.gutter),
            child: Text(
              AppStrings.historyLoadFailed,
              style: context.textStyles.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      _ => const SizedBox.expand(key: ValueKey('loading')),
    };

    return AnimatedSwitcher(duration: AppDurations.medium, child: child);
  }
}
