import 'package:flutter/foundation.dart';

@immutable
class Conversation {
  const Conversation({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  static const int maxTitleLength = 48;

  final String id;
  final String title;
  final DateTime createdAt;

  /// Time of the latest message; history is ordered by this.
  final DateTime updatedAt;

  /// Derives a title from the first prompt: first line, whitespace
  /// collapsed, cut at a word boundary with an ellipsis if too long.
  ///
  /// A local model can later replace this with a generated summary title.
  static String titleFromPrompt(String prompt) {
    final firstLine = prompt.trim().split('\n').first;
    final collapsed = firstLine.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.length <= maxTitleLength) return collapsed;

    final cut = collapsed.substring(0, maxTitleLength);
    final lastSpace = cut.lastIndexOf(' ');
    final base = lastSpace > maxTitleLength ~/ 2 ? cut.substring(0, lastSpace) : cut;
    return '${base.trimRight()}…';
  }

  Conversation copyWith({String? title, DateTime? updatedAt}) {
    return Conversation(
      id: id,
      title: title ?? this.title,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Conversation &&
      other.id == id &&
      other.title == title &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(id, title, createdAt, updatedAt);
}
