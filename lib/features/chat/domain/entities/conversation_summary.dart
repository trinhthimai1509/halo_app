import 'package:flutter/foundation.dart';

import 'conversation.dart';

/// A conversation plus what the history list needs to preview it.
@immutable
class ConversationSummary {
  const ConversationSummary({
    required this.conversation,
    this.lastMessagePreview,
  });

  final Conversation conversation;
  final String? lastMessagePreview;

  String get id => conversation.id;

  @override
  bool operator ==(Object other) =>
      other is ConversationSummary &&
      other.conversation == conversation &&
      other.lastMessagePreview == lastMessagePreview;

  @override
  int get hashCode => Object.hash(conversation, lastMessagePreview);
}
