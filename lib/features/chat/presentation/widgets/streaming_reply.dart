import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/chat_controller.dart';
import 'assistant_message.dart';

/// The in-progress assistant reply. The only widget that rebuilds per
/// streamed chunk.
class StreamingReply extends ConsumerWidget {
  const StreamingReply({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final content = ref.watch(
      chatControllerProvider.select((state) => state.streamingReply?.content),
    );
    return AssistantMessage(content: content, isStreaming: true);
  }
}
