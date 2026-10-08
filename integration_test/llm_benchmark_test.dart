// On-device benchmark for the real local model. Not part of `flutter test`.
//
// Run on a connected Android device with the model installed
// (see docs/LOCAL_AI.md):
//
//   flutter test integration_test/llm_benchmark_test.dart -d <device-id>
//
// Metrics are printed as `[LLM] …` lines (load time, TTFT, tokens/s, RSS);
// replies are printed in full for manual quality review.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:offline_ai_chat/features/chat/domain/assistant_instructions.dart';
import 'package:offline_ai_chat/features/local_ai/data/llama_cpp/llama_cpp_local_ai_service.dart';
import 'package:offline_ai_chat/features/local_ai/domain/local_ai_service.dart';

import 'benchmark_prompts.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late LlamaCppLocalAiService ai;

  setUpAll(() async {
    ai = LlamaCppLocalAiService();
    final stopwatch = Stopwatch()..start();
    await ai.initialize();
    debugPrint('[BENCH] initialize_ms=${stopwatch.elapsedMilliseconds}');
  });

  tearDownAll(() => ai.dispose());

  final system = AiMessage(
    role: AiRole.system,
    content: AssistantInstructions.systemPrompt(DateTime.now()),
  );

  Future<String> ask(List<AiMessage> history, String prompt) async {
    final messages = [
      system,
      ...history,
      AiMessage(role: AiRole.user, content: prompt),
    ];
    var chunks = 0;
    final reply = StringBuffer();
    await for (final delta in ai.generate(GenerationRequest(messages: messages))) {
      chunks++;
      reply.write(delta);
    }
    debugPrint('[BENCH] ui_chunks=$chunks');
    return reply.toString();
  }

  for (final benchmark in benchmarkCases) {
    testWidgets('benchmark ${benchmark.id}', (tester) async {
      final history = <AiMessage>[];
      for (final turn in benchmark.turns) {
        final reply = await ask(history, turn);
        debugPrint('[BENCH] case=${benchmark.id}\n>>> $turn\n<<< $reply\n');
        expect(reply.trim(), isNotEmpty);
        history
          ..add(AiMessage(role: AiRole.user, content: turn))
          ..add(AiMessage(role: AiRole.assistant, content: reply));
      }
    }, timeout: const Timeout(Duration(minutes: 25)));
  }

  testWidgets('stop interrupts native generation promptly', (tester) async {
    final reply = StringBuffer();
    final enoughText = Completer<void>();
    final subscription = ai
        .generate(
          GenerationRequest(
            messages: [system, const AiMessage(role: AiRole.user, content: cancellationPrompt)],
          ),
        )
        .listen((delta) {
      reply.write(delta);
      if (reply.length > 120 && !enoughText.isCompleted) enoughText.complete();
    });

    await enoughText.future;
    final stopwatch = Stopwatch()..start();
    await subscription.cancel();
    final cancelMs = stopwatch.elapsedMilliseconds;
    final partial = reply.toString();

    // No more text may arrive after cancel.
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(reply.toString(), partial);

    // The next generation can start: the native loop really stopped.
    stopwatch.reset();
    final next = await ask(const [], 'Say "ok".');
    debugPrint(
      '[BENCH] cancel_ms=$cancelMs partial_chars=${partial.length} '
      'next_generation_ms=${stopwatch.elapsedMilliseconds} next="$next"',
    );
    expect(next.trim(), isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
