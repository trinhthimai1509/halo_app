/// The assistant's system prompt. Kept minimal and neutral on purpose:
/// small local models follow short instructions best, and every token here
/// is paid for on each turn.
abstract final class AssistantInstructions {
  static const String systemPrompt =
      'You are a helpful assistant. Respond in the same language as the user.';
}
