import 'package:flutter/foundation.dart';

import 'message_role.dart';

@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final String conversationId;
  final MessageRole role;
  final String content;
  final DateTime createdAt;

  bool get isUser => role == MessageRole.user;

  ChatMessage copyWith({String? content}) {
    return ChatMessage(
      id: id,
      conversationId: conversationId,
      role: role,
      content: content ?? this.content,
      createdAt: createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ChatMessage &&
      other.id == id &&
      other.conversationId == conversationId &&
      other.role == role &&
      other.content == content &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(id, conversationId, role, content, createdAt);

  @override
  String toString() => 'ChatMessage($id, ${role.name}, ${content.length} chars)';
}
