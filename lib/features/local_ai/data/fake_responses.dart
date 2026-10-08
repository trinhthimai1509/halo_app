import '../domain/local_ai_service.dart';

/// Canned replies for [FakeLocalAiService]. Development content only.
abstract final class FakeResponses {
  static String replyTo(List<AiMessage> messages) {
    final prompt = messages
        .lastWhere(
          (message) => message.role == AiRole.user,
          orElse: () => const AiMessage(role: AiRole.user, content: ''),
        )
        .content
        .toLowerCase();

    if (prompt.contains('explain')) return _explain;
    if (prompt.contains('write') || prompt.contains('note')) return _write;
    if (prompt.contains('idea')) return _ideas;
    if (prompt.contains('help')) return _capabilities;
    return _fallback;
  }

  static const String _explain =
      'On-device AI means the model runs directly on your phone instead of '
      'on a remote server.\n\n'
      'When you send a message, the app turns your text into tokens, feeds '
      'them to a compact language model stored locally, and the model '
      'predicts the reply one token at a time. That is why the answer appears '
      'progressively.\n\n'
      'The main benefits are privacy — nothing leaves the device — and the '
      'fact that it keeps working without a connection. The trade-off is that '
      'local models are smaller, so very long or highly specialised answers '
      'can be less detailed.';

  static const String _write =
      'Here is a short, warm note you can adapt:\n\n'
      'Hi Sam,\n\n'
      'I just wanted to say thank you for your help this week. You made a '
      'tricky project feel manageable, and I really appreciated how patient '
      'you were with all my questions.\n\n'
      'Coffee is on me next time.\n\n'
      'Best,\nAlex';

  static const String _ideas =
      'A few ideas for a slow, restful weekend:\n\n'
      '• Take a long morning walk somewhere green, without headphones.\n'
      '• Cook one unhurried meal from a recipe you have never tried.\n'
      '• Visit a small museum, library or bookshop and browse with no goal.\n'
      '• Leave one evening completely unplanned.\n\n'
      'Would you like me to turn one of these into a simple plan?';

  static const String _capabilities =
      'I can help you think through ideas, explain concepts, draft and edit '
      'writing, summarise notes, or plan things step by step.\n\n'
      'Everything runs locally, so you can use me offline and your '
      'conversations stay private. What would you like to start with?';

  static const String _fallback =
      'That is a great question. This build uses a simulated on-device model, '
      'so this reply is a placeholder that streams in the same way a real '
      'local model would.\n\n'
      'Once the local model is connected, you will get a genuine answer here, '
      'generated entirely on your device.';
}
