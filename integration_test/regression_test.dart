// Bounded on-device regression for the real local model (Phase 2, A–C).
//
//   flutter test integration_test/regression_test.dart -d <device> --no-uninstall
//
// A. normal completion -> immediate next generation
// B. Stop -> native CPU drops -> immediate next generation is not affected
//    by a stale cancellation
// C. repeated consecutive generations + a sustained run capped at 3 minutes
//
// Per-generation metrics come from the service's `[LLM]` lines; this test
// prints `[REG]` verdict lines. Uses the production thread default.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:offline_ai_chat/features/chat/domain/assistant_instructions.dart';
import 'package:offline_ai_chat/features/local_ai/data/llama_cpp/llama_cpp_local_ai_service.dart';
import 'package:offline_ai_chat/features/local_ai/domain/local_ai_service.dart';

import 'benchmark_prompts.dart';

const AiMessage _system = AiMessage(
  role: AiRole.system,
  content: AssistantInstructions.systemPrompt,
);

const Duration _maxGap = Duration(seconds: 10);
const Duration _sustainedBudget = Duration(minutes: 3);

class _Result {
  _Result(this.verdict, this.text, this.pieces, this.elapsed);
  final String verdict; // ok | STALL | TIMEOUT | ERROR
  final String text;
  final int pieces;
  final Duration elapsed;
}

Future<_Result> _generate(
  LocalAiService ai,
  List<AiMessage> turns, {
  required int maxTokens,
  Duration timeout = const Duration(seconds: 120),
}) async {
  final done = Completer<String>();
  final text = StringBuffer();
  var pieces = 0;
  final clock = Stopwatch()..start();
  var last = Duration.zero;

  final subscription = ai
      .generate(
        GenerationRequest(messages: [_system, ...turns], maxTokens: maxTokens),
      )
      .listen(
        (delta) {
          pieces++;
          last = clock.elapsed;
          text.write(delta);
        },
        onError: (Object e) => done.isCompleted ? null : done.complete('ERROR $e'),
        onDone: () => done.isCompleted ? null : done.complete('ok'),
      );
  final guard = Timer.periodic(const Duration(milliseconds: 250), (_) {
    if (done.isCompleted) return;
    if (clock.elapsed > timeout) return done.complete('TIMEOUT');
    if (pieces > 0 && clock.elapsed - last > _maxGap) done.complete('STALL');
  });
  final verdict = await done.future;
  guard.cancel();
  if (verdict != 'ok') await subscription.cancel();
  return _Result(verdict, text.toString(), pieces, clock.elapsed);
}

AiMessage _user(String text) => AiMessage(role: AiRole.user, content: text);

int _processCpuTicks() {
  final stat = File('/proc/self/stat').readAsStringSync();
  final fields = stat.substring(stat.lastIndexOf(')') + 2).split(' ');
  return int.parse(fields[11]) + int.parse(fields[12]);
}

Future<double> _coresBusy(Duration window) async {
  final before = _processCpuTicks();
  await Future<void>.delayed(window);
  return (_processCpuTicks() - before) / 100 / (window.inMilliseconds / 1000);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late LlamaCppLocalAiService ai;

  setUpAll(() async {
    ai = LlamaCppLocalAiService();
    await ai.initialize();
    debugPrint('[REG] threads=${ai.config.threads}');
  });

  tearDownAll(() => ai.dispose());

  testWidgets('A: normal completion then immediate next generation',
      (tester) async {
    final first = await _generate(
      ai,
      [_user('What is the difference between RAM and storage?')],
      maxTokens: 64,
    );
    final gap = Stopwatch()..start();
    final second = await _generate(
      ai,
      [_user('Xin chào. Bạn có thể làm gì?')],
      maxTokens: 64,
    );
    debugPrint('[REG] A first=${first.verdict}/${first.pieces} '
        'second=${second.verdict}/${second.pieces} '
        'second_total_ms=${gap.elapsedMilliseconds}');
    expect(first.verdict, 'ok');
    expect(second.verdict, 'ok');
    expect(second.pieces, greaterThan(10));
  });

  testWidgets('B: stop, native CPU drops, next generation unaffected',
      (tester) async {
    final text = StringBuffer();
    var pieces = 0;
    final enough = Completer<void>();
    final subscription = ai
        .generate(
          const GenerationRequest(messages: [
            _system,
            AiMessage(role: AiRole.user, content: cancellationPrompt),
          ]),
        )
        .listen((delta) {
      text.write(delta);
      if (++pieces >= 32 && !enough.isCompleted) enough.complete();
    });
    await enough.future.timeout(const Duration(seconds: 60));
    final during = await _coresBusy(const Duration(seconds: 1));
    await subscription.cancel();
    final atStop = text.length;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final after = await _coresBusy(const Duration(seconds: 1));

    // A stale abort flag would end this one almost immediately; it must run
    // to its cap (or a natural end well past a handful of tokens).
    final next = await _generate(
      ai,
      [
        _user('Giải thích trí tuệ nhân tạo cho một học sinh 12 tuổi bằng '
            'ngôn ngữ đơn giản.'),
      ],
      maxTokens: 48,
    );
    debugPrint('[REG] B cores_during=${during.toStringAsFixed(2)} '
        'cores_after_stop=${after.toStringAsFixed(2)} '
        'text_after_stop=${text.length - atStop} '
        'next=${next.verdict}/${next.pieces}');
    expect(text.length, atStop);
    expect(after, lessThan(0.5));
    expect(next.verdict, 'ok');
    expect(next.pieces, greaterThanOrEqualTo(30));
  });

  testWidgets('C1: repeated consecutive generations', (tester) async {
    final prompts = [
      for (final c in benchmarkCases) c.turns.first,
    ].take(5);
    var i = 0;
    for (final prompt in prompts) {
      final r = await _generate(ai, [_user(prompt)], maxTokens: 96);
      debugPrint('[REG] C1 #${++i} ${r.verdict}/${r.pieces} '
          'ms=${r.elapsed.inMilliseconds}');
      expect(r.verdict, 'ok');
    }
  }, timeout: const Timeout(Duration(minutes: 8)));

  testWidgets('C2: bounded sustained generation (3 min)', (tester) async {
    final budget = Stopwatch()..start();
    var runs = 0;
    var totalPieces = 0;
    while (budget.elapsed < _sustainedBudget) {
      final prompt = benchmarkCases[runs % benchmarkCases.length].turns.first;
      final r = await _generate(ai, [_user(prompt)], maxTokens: 256);
      runs++;
      totalPieces += r.pieces;
      debugPrint('[REG] C2 run=$runs ${r.verdict}/${r.pieces} '
          'ms=${r.elapsed.inMilliseconds} '
          'elapsed_s=${budget.elapsed.inSeconds}');
      expect(r.verdict, 'ok', reason: 'pathological stall or timeout');
    }
    debugPrint('[REG] C2 done runs=$runs pieces=$totalPieces '
        'seconds=${budget.elapsed.inSeconds}');
  }, timeout: const Timeout(Duration(minutes: 6)));
}
