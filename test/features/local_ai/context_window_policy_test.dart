import 'package:flutter_test/flutter_test.dart';
import 'package:offline_ai_chat/core/error/app_exception.dart';
import 'package:offline_ai_chat/features/local_ai/domain/context_window_policy.dart';
import 'package:offline_ai_chat/features/local_ai/domain/local_ai_service.dart';

void main() {
  // One token per character keeps the arithmetic obvious.
  Future<int> countChars(String text) async => text.length;

  AiMessage user(String text) => AiMessage(role: AiRole.user, content: text);
  AiMessage assistant(String text) =>
      AiMessage(role: AiRole.assistant, content: text);
  const system = AiMessage(role: AiRole.system, content: 'sys');

  // Budget = 200 - 50 - 0 = 150; each message costs length + 10.
  const policy = ContextWindowPolicy(
    contextSize: 200,
    maxNewTokens: 50,
    perMessageOverhead: 10,
    safetyMargin: 0,
  );

  test('keeps everything when it fits', () async {
    final messages = [system, user('a' * 20), assistant('b' * 20), user('c')];

    expect(await policy.fit(messages, countChars), messages);
  });

  test('drops the oldest turns first and always keeps the system prompt',
      () async {
    final messages = [
      system, // 13
      user('1' * 40), // 50  -> does not fit any more
      assistant('2' * 40), // 50
      user('3' * 40), // 50
      assistant('4' * 20), // 30
      user('5'), // 11
    ];

    final window = await policy.fit(messages, countChars);

    // 150 - 13 = 137: fits 11 + 30 + 50 = 91, then 50 more would be 141.
    expect(window.map((m) => m.content), ['sys', '3' * 40, '4' * 20, '5']);
  });

  test('never starts the kept history with an assistant turn', () async {
    final messages = [
      system,
      user('1' * 60),
      assistant('2' * 50), // fits by size, but would lead the window
      user('3' * 50),
    ];

    final window = await policy.fit(messages, countChars);

    expect(window.first, system);
    expect(window[1].role, AiRole.user);
    expect(window.last.content, '3' * 50);
  });

  test('rejects a current message that alone exceeds the budget', () async {
    await expectLater(
      policy.fit([system, user('x' * 500)], countChars),
      throwsA(isA<GenerationException>()),
    );
  });

  test('maxPromptTokens caps the budget below the context limit', () {
    const capped = ContextWindowPolicy(
      contextSize: 4096,
      maxNewTokens: 1024,
      maxPromptTokens: 1536,
    );
    expect(capped.promptBudget, 1536);
    const loose = ContextWindowPolicy(
      contextSize: 4096,
      maxNewTokens: 1024,
      maxPromptTokens: 9000,
    );
    expect(loose.promptBudget, 4096 - 1024 - 64);
  });
}
