// Controlled decode-thread comparison. One configuration per run:
//
//   flutter test integration_test/thread_sweep_test.dart -d <device> \
//     --dart-define=LLM_THREADS=2 --dart-define=LLM_SEED=42
//
// Everything except the thread count is identical between runs (model,
// n_ctx, sampling, seed, prompts, caps). Per-token metrics come from the
// service's `[LLM] generation_*` lines; this test adds `[SWEEP]` lines for
// stall-guard verdicts and the Stop/native-CPU check.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:offline_ai_chat/features/chat/domain/assistant_instructions.dart';
import 'package:offline_ai_chat/features/local_ai/data/llama_cpp/llama_cpp_local_ai_service.dart';
import 'package:offline_ai_chat/features/local_ai/data/llama_cpp/llm_model_config.dart';
import 'package:offline_ai_chat/features/local_ai/domain/local_ai_service.dart';

const int _threads = int.fromEnvironment(
  'LLM_THREADS',
  defaultValue: LlmModelConfig.defaultAndroidThreads,
);
const int _seed = int.fromEnvironment('LLM_SEED', defaultValue: 42);

const AiMessage _system = AiMessage(
  role: AiRole.system,
  content: AssistantInstructions.systemPrompt,
);

/// Stall guard: abort when one gap exceeds this...
const Duration _maxGap = Duration(seconds: 10);

/// ...or when decode speed after [_rateCheckAfter] pieces is below this.
const double _minTokensPerSecond = 0.5;
const int _rateCheckAfter = 32;

class _Outcome {
  _Outcome(this.verdict, this.text, this.pieces);
  final String verdict; // ok | STALL_GAP | STALL_RATE | TIMEOUT
  final String text;
  final int pieces;
}

/// Streams one reply with stall guards and a hard timeout.
Future<_Outcome> _run(
  LocalAiService ai,
  String prompt, {
  required int maxTokens,
  required Duration timeout,
}) async {
  final done = Completer<String>();
  final text = StringBuffer();
  var pieces = 0;
  final clock = Stopwatch()..start();
  var lastPiece = clock.elapsed;
  Duration? firstPiece;

  late final StreamSubscription<String> subscription;
  subscription = ai
      .generate(
        GenerationRequest(
          messages: [_system, AiMessage(role: AiRole.user, content: prompt)],
          maxTokens: maxTokens,
        ),
      )
      .listen(
        (delta) {
          pieces++;
          firstPiece ??= clock.elapsed;
          lastPiece = clock.elapsed;
          text.write(delta);
        },
        onError: (Object e) => done.isCompleted ? null : done.complete('ERROR $e'),
        onDone: () => done.isCompleted ? null : done.complete('ok'),
      );

  final guard = Timer.periodic(const Duration(milliseconds: 250), (_) {
    if (done.isCompleted) return;
    final now = clock.elapsed;
    if (now > timeout) return done.complete('TIMEOUT');
    if (firstPiece != null && now - lastPiece > _maxGap) {
      return done.complete('STALL_GAP');
    }
    if (pieces >= _rateCheckAfter) {
      final seconds = (now - firstPiece!).inMilliseconds / 1000;
      if (pieces / seconds < _minTokensPerSecond) done.complete('STALL_RATE');
    }
  });

  final verdict = await done.future;
  guard.cancel();
  if (verdict != 'ok') await subscription.cancel();
  return _Outcome(verdict, text.toString(), pieces);
}

/// Process CPU time (user + system) in clock ticks (100 Hz on Android).
int _processCpuTicks() {
  final stat = File('/proc/self/stat').readAsStringSync();
  final fields = stat.substring(stat.lastIndexOf(')') + 2).split(' ');
  return int.parse(fields[11]) + int.parse(fields[12]); // utime, stime
}

/// Average CPU cores used by this process over [window].
Future<double> _coresBusy(Duration window) async {
  final before = _processCpuTicks();
  await Future<void>.delayed(window);
  final ticks = _processCpuTicks() - before;
  return ticks / 100 / (window.inMilliseconds / 1000);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late LlamaCppLocalAiService ai;

  setUpAll(() async {
    ai = LlamaCppLocalAiService(
      config: LlmModelConfig.qwen35_2b.copyWith(threads: _threads, seed: _seed),
    );
    final clock = Stopwatch()..start();
    await ai.initialize();
    debugPrint('[SWEEP] threads=$_threads seed=$_seed '
        'initialize_ms=${clock.elapsedMilliseconds}');
  });

  tearDownAll(() => ai.dispose());

  testWidgets('short', (tester) async {
    final r = await _run(
      ai,
      'Xin chào. Bạn có thể làm gì?',
      maxTokens: 64,
      timeout: const Duration(seconds: 60),
    );
    debugPrint('[SWEEP] case=short verdict=${r.verdict} pieces=${r.pieces}');
    debugPrint('[SWEEP] text=${r.text.replaceAll('\n', ' ')}');
  });

  testWidgets('medium_sustained', (tester) async {
    final r = await _run(
      ai,
      'Giải thích trí tuệ nhân tạo cho một học sinh 12 tuổi bằng ngôn ngữ '
      'đơn giản.',
      maxTokens: 256,
      timeout: const Duration(seconds: 150),
    );
    debugPrint('[SWEEP] case=medium verdict=${r.verdict} pieces=${r.pieces}');
  });

  testWidgets('stop_then_next', (tester) async {
    final text = StringBuffer();
    var pieces = 0;
    final enough = Completer<void>();
    final subscription = ai
        .generate(
          const GenerationRequest(
            messages: [
              _system,
              AiMessage(
                role: AiRole.user,
                content:
                    'Write a detailed, 20-step guide to learning to cook at home.',
              ),
            ],
          ),
        )
        .listen((delta) {
      text.write(delta);
      if (++pieces >= 48 && !enough.isCompleted) enough.complete();
    });

    await enough.future.timeout(const Duration(seconds: 45));
    final busyBefore = await _coresBusy(const Duration(seconds: 1));

    final clock = Stopwatch()..start();
    await subscription.cancel();
    final cancelMs = clock.elapsedMilliseconds;
    final atCancel = text.length;

    await Future<void>.delayed(const Duration(milliseconds: 300));
    final busyAfter = await _coresBusy(const Duration(seconds: 1));
    final leaked = text.length - atCancel;

    clock.reset();
    final next = await _run(
      ai,
      'Say "ok".',
      maxTokens: 16,
      timeout: const Duration(seconds: 30),
    );
    debugPrint(
      '[SWEEP] case=stop cancel_ms=$cancelMs pieces_before_stop=$pieces '
      'cores_busy_during=${busyBefore.toStringAsFixed(2)} '
      'cores_busy_after_stop=${busyAfter.toStringAsFixed(2)} '
      'text_after_stop=$leaked next_verdict=${next.verdict} '
      'next_total_ms=${clock.elapsedMilliseconds} '
      'next="${next.text.replaceAll('\n', ' ')}"',
    );
    expect(leaked, 0);
    expect(next.verdict, 'ok');
  });
}
