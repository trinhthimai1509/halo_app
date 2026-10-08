import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_durations.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../state/chat_controller.dart';
import 'chat_empty_state.dart';
import 'message_list.dart';

enum _BodyMode { loading, empty, conversation }

/// Cross-fades between the welcome state and the conversation.
class ChatBody extends ConsumerWidget {
  const ChatBody({super.key});

  /// Fraction of the height faded at the top and bottom edges, so messages
  /// dissolve under the header and composer instead of being hard-clipped.
  static const double _edgeFade = 0.035;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(
      chatControllerProvider.select(
        (state) => state.isLoading
            ? _BodyMode.loading
            : state.isEmpty
                ? _BodyMode.empty
                : _BodyMode.conversation,
      ),
    );
    // Switching conversation always passes through `loading` or `empty`, so
    // each conversation gets a fresh MessageList without keying by id (which
    // would cross-fade again when a new chat receives its id).
    final Widget child = switch (mode) {
      _BodyMode.loading => const SizedBox.expand(key: ValueKey('loading')),
      _BodyMode.empty => const ChatEmptyState(key: ValueKey('empty')),
      _BodyMode.conversation => const _FadedEdges(
          key: ValueKey('conversation'),
          child: MessageList(),
        ),
    };

    return AnimatedSwitcher(
      duration: context.reduceMotion ? Duration.zero : AppDurations.slow,
      switchInCurve: AppCurves.emphasized,
      switchOutCurve: AppCurves.exit,
      child: child,
    );
  }
}

class _FadedEdges extends StatelessWidget {
  const _FadedEdges({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0x00000000),
          Color(0xFF000000),
          Color(0xFF000000),
          Color(0x00000000),
        ],
        stops: [0, ChatBody._edgeFade, 1 - ChatBody._edgeFade, 1],
      ).createShader(bounds),
      child: child,
    );
  }
}
