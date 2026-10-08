import '../../../core/error/app_exception.dart';
import 'local_ai_service.dart';

/// Counts tokens for [text] with the loaded model's tokenizer.
typedef TokenCounter = Future<int> Function(String text);

/// Decides which messages are sent to the model so the prompt plus the reply
/// fit in the context window.
///
/// Policy (deliberately simple, isolated so it can evolve):
/// 1. Leading system messages are always kept.
/// 2. The newest message (the current user turn) is always kept.
/// 3. Older messages are added newest → oldest while they fit.
/// 4. The kept history never starts with an assistant turn.
class ContextWindowPolicy {
  const ContextWindowPolicy({
    required this.contextSize,
    required this.maxNewTokens,
    this.perMessageOverhead = 8,
    this.safetyMargin = 64,
    this.maxPromptTokens,
  });

  /// Model context window (`n_ctx`) in tokens.
  final int contextSize;

  /// Tokens reserved for the reply.
  final int maxNewTokens;

  /// Chat-template tokens added around each message
  /// (e.g. `<|im_start|>user\n … <|im_end|>\n`).
  final int perMessageOverhead;

  /// Slack for the generation prompt and counting inaccuracies.
  final int safetyMargin;

  /// Optional cap below the context limit, to bound prompt-processing time.
  final int? maxPromptTokens;

  int get promptBudget {
    final limit = contextSize - maxNewTokens - safetyMargin;
    final cap = maxPromptTokens;
    return cap == null || cap > limit ? limit : cap;
  }

  Future<List<AiMessage>> fit(
    List<AiMessage> messages,
    TokenCounter countTokens,
  ) async {
    if (messages.isEmpty) return messages;

    final system = messages.takeWhile((m) => m.role == AiRole.system).toList();
    final conversation = messages.skip(system.length).toList();
    if (conversation.isEmpty) return system;

    var remaining = promptBudget;
    for (final message in system) {
      remaining -= await _cost(message, countTokens);
    }

    final kept = <AiMessage>[];
    for (var i = conversation.length - 1; i >= 0; i--) {
      final message = conversation[i];
      final cost = await _cost(message, countTokens);
      final isCurrentTurn = i == conversation.length - 1;
      if (cost > remaining) {
        if (isCurrentTurn) {
          throw const GenerationException(
            'The message is too long for the model context window.',
          );
        }
        break;
      }
      remaining -= cost;
      kept.add(message);
    }

    final window = kept.reversed.toList();
    while (window.length > 1 && window.first.role == AiRole.assistant) {
      window.removeAt(0);
    }
    return [...system, ...window];
  }

  Future<int> _cost(AiMessage message, TokenCounter countTokens) async =>
      await countTokens(message.content) + perMessageOverhead;
}
