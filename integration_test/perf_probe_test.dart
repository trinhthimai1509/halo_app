// Prompt-processing performance probe (investigation harness, real device).
//
//   flutter test integration_test/perf_probe_test.dart -d <serial> --no-uninstall
//     [--dart-define=PROBE=threads|snapshot|all]   (default: all)
//
// E1 `threads`: prompt-processing (prefill) speed vs n_threads_batch with
//    decode threads fixed at the validated 2. Same prompts every time.
// E2 `snapshot`: can the processed system prompt be saved once
//    (llama_state_save_file) and restored per request so only the
//    conversation is evaluated? Verified by comparing outputs with and
//    without the snapshot under the same seed: they must be identical.
// Results: <external files>/qe/perf_*.json and `[PERF]` lines.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:llamadart/llamadart.dart';
import 'package:offline_ai_chat/features/chat/domain/assistant_instructions.dart';
import 'package:offline_ai_chat/features/local_ai/data/llama_cpp/llm_model_config.dart';
import 'package:offline_ai_chat/features/local_ai/data/llama_cpp/model_file_locator.dart';
import 'package:path_provider/path_provider.dart';

const String _probe = String.fromEnvironment('PROBE', defaultValue: 'all');
const LlmModelConfig _c = LlmModelConfig.qwen35_2b;

LlamaChatMessage _m(LlamaChatRole r, String t) =>
    LlamaChatMessage.fromText(role: r, text: t);

String get _system => AssistantInstructions.systemPrompt(DateTime.now());

List<LlamaChatMessage> _short(String q) => [
      _m(LlamaChatRole.system, _system),
      _m(LlamaChatRole.user, q),
    ];

const _filler =
    'Phở là món ăn truyền thống nổi tiếng của Việt Nam, gồm bánh phở, nước '
    'dùng hầm từ xương bò hoặc gà trong nhiều giờ, thêm thịt, hành lá, rau '
    'thơm và gia vị như quế, hồi, gừng nướng. Mỗi vùng miền có cách nấu riêng: '
    'phở Hà Nội thường thanh, ít rau; phở miền Nam ăn kèm giá, húng quế và '
    'tương. Người Việt ăn phở vào bữa sáng nhưng cũng có thể ăn bất cứ lúc '
    'nào trong ngày. Khi nấu tại nhà, nên chần xương để nước dùng trong, hớt '
    'bọt thường xuyên và nêm nếm vừa phải để giữ vị ngọt tự nhiên.';

List<LlamaChatMessage> get _long => [
      _m(LlamaChatRole.system, _system),
      for (var i = 1; i <= 6; i++) ...[
        _m(LlamaChatRole.user, 'Kể cho tôi thêm về món ăn Việt Nam, phần $i.'),
        _m(LlamaChatRole.assistant, 'Phần $i. $_filler'),
      ],
      _m(LlamaChatRole.user, 'Tóm tắt ngắn gọn các phần trên.'),
    ];

GenerationParams _params(int maxTokens, {required bool reuse}) =>
    GenerationParams(
      maxTokens: maxTokens,
      temp: _c.temperature,
      topK: _c.topK,
      topP: _c.topP,
      minP: _c.minP,
      penalty: 1.0,
      presencePenalty: _c.presencePenalty,
      seed: 42,
      reusePromptPrefix: reuse,
      streamBatchTokenThreshold: 1,
    );

Future<LlamaEngine> _load(int batchThreads) async {
  final path = await const ModelFileLocator().find(_c.fileName);
  final engine = LlamaEngine(LlamaBackend());
  await engine.loadModel(
    path!,
    modelParams: ModelParams(
      contextSize: _c.contextSize,
      gpuLayers: 0,
      preferredBackend: GpuBackend.cpu,
      numberOfThreads: _c.threads,
      numberOfThreadsBatch: batchThreads,
    ),
  );
  return engine;
}

/// One chat completion; returns text, TTFT and native perf counters.
Future<Map<String, Object?>> _run(
  LlamaEngine e,
  List<LlamaChatMessage> msgs,
  int maxTokens, {
  bool reuse = false,
}) async {
  final w = Stopwatch()..start();
  int? ttft;
  final text = StringBuffer();
  await for (final chunk in e.create(
    msgs,
    params: _params(maxTokens, reuse: reuse),
    enableThinking: false,
  )) {
    final t = chunk.choices.isEmpty ? null : chunk.choices.first.delta.content;
    if (t == null || t.isEmpty) continue;
    ttft ??= w.elapsedMilliseconds;
    text.write(t);
  }
  final p = await e.getPerformanceContext();
  return {
    'ttft_ms': ttft,
    'total_ms': w.elapsedMilliseconds,
    'prompt_eval_tokens': p?.promptEvalTokens,
    'prompt_eval_ms': p?.promptEvalMs.round(),
    'prefill_tok_s': p == null || p.promptEvalMs == 0
        ? null
        : (p.promptEvalTokens * 1000 / p.promptEvalMs).toStringAsFixed(1),
    'gen_tokens': p?.evalTokens,
    'decode_tok_s': p == null || p.evalMs == 0
        ? null
        : (p.evalTokens * 1000 / p.evalMs).toStringAsFixed(2),
    'text': text.toString(),
  };
}

Future<void> _save(String name, Object data) async {
  final dir = Directory('${(await getExternalStorageDirectory())!.path}/qe');
  await dir.create(recursive: true);
  await File('${dir.path}/$name.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(data));
}

void _log(String s) => debugPrint('[PERF] $s');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('E1 prefill vs n_threads_batch', (tester) async {
    await tester.runAsync(() async {
      final results = <Map<String, Object?>>[];
      for (final batch in [2, 4, 6, 8]) {
        final load = Stopwatch()..start();
        final e = await _load(batch);
        final loadMs = load.elapsedMilliseconds;
        try {
          await _run(e, _short('Xin chào'), 1); // warm-up
          for (final q in [
            'Thủ đô của Việt Nam là thành phố nào?',
            'Viết một câu chúc mừng sinh nhật ngắn gọn dành cho mẹ.',
            'Giải thích ngắn gọn trí tuệ nhân tạo là gì.',
          ]) {
            final r = await _run(e, _short(q), 48);
            results.add({'batch_threads': batch, 'case': 'short', 'load_ms': loadMs, ...r});
            _log('batch=$batch short ${jsonEncode({...r}..remove('text'))}');
          }
          final r = await _run(e, _long, 16);
          results.add({'batch_threads': batch, 'case': 'long', 'load_ms': loadMs, ...r});
          _log('batch=$batch long ${jsonEncode({...r}..remove('text'))}');
        } finally {
          await e.dispose();
        }
      }
      await _save('perf_threads', results);
    });
  }, skip: _probe == 'snapshot', timeout: const Timeout(Duration(minutes: 25)));

  testWidgets('E2 system-prompt state snapshot', (tester) async {
    await tester.runAsync(() async {
      final e = await _load(_c.threads);
      final report = <String, Object?>{};
      try {
        final now = DateTime.now();
        final system = AssistantInstructions.systemPrompt(now);
        // The Qwen3.5 template refuses a system-only conversation, so the
        // system block is cut out of a fully rendered prompt.
        final rendered = (await e.chatTemplate(
          [_m(LlamaChatRole.system, system), _m(LlamaChatRole.user, 'x')],
          enableThinking: false,
        ))
            .prompt;
        final prefix =
            rendered.substring(0, rendered.indexOf('<|im_start|>user'));
        final conversations = <String, List<LlamaChatMessage>>{
          'q1': [_m(LlamaChatRole.system, system), _m(LlamaChatRole.user, 'Thủ đô của Việt Nam là thành phố nào?')],
          'q2': [_m(LlamaChatRole.system, system), _m(LlamaChatRole.user, 'Viết một câu chúc mừng sinh nhật ngắn gọn dành cho mẹ.')],
          'multi': [
            _m(LlamaChatRole.system, system),
            _m(LlamaChatRole.user, 'Tên tôi là Minh.'),
            _m(LlamaChatRole.assistant, 'Chào Minh! Rất vui được làm quen với bạn.'),
            _m(LlamaChatRole.user, 'Tên tôi là gì?'),
          ],
        };
        // 1. Token-level prefix check.
        final prefixTokens = await e.tokenize(prefix, addSpecial: false);
        for (final entry in conversations.entries) {
          final full = (await e.chatTemplate(entry.value, enableThinking: false)).prompt;
          final fullTokens = await e.tokenize(full, addSpecial: false);
          var same = fullTokens.length >= prefixTokens.length;
          for (var i = 0; same && i < prefixTokens.length; i++) {
            same = fullTokens[i] == prefixTokens[i];
          }
          report['${entry.key}_text_prefix'] = full.startsWith(prefix);
          report['${entry.key}_token_prefix'] = same;
          report['${entry.key}_tokens'] = fullTokens.length;
        }
        report['prefix_tokens'] = prefixTokens.length;

        // 2. Build the snapshot: evaluate the prefix only (maxTokens 0).
        final build = Stopwatch()..start();
        await e.generate(prefix, params: _params(0, reuse: false)).drain<void>();
        final path = '${(await getApplicationSupportDirectory()).path}/sys_prefix.state';
        final saved = await e.stateSaveFile(path, tokens: prefixTokens);
        report['snapshot_build_ms'] = build.elapsedMilliseconds;
        report['snapshot_saved'] = saved;
        report['snapshot_bytes'] = File(path).lengthSync();

        // 3. Baseline vs snapshot, same seed: outputs must be identical.
        for (final entry in conversations.entries) {
          final base = await _run(e, entry.value, 48);
          final load = Stopwatch()..start();
          final loaded = await e.stateLoadFile(path, tokenCapacity: _c.contextSize);
          final loadMs = load.elapsedMilliseconds;
          final snap = await _run(e, entry.value, 48, reuse: true);
          report[entry.key] = {
            'base': base,
            'snapshot': snap,
            'state_load_ms': loadMs,
            'loaded_tokens': loaded.tokens.length,
            'identical_output': base['text'] == snap['text'],
          };
          _log('${entry.key} identical=${base['text'] == snap['text']} '
              'base_ttft=${base['ttft_ms']} base_eval=${base['prompt_eval_tokens']} '
              'snap_ttft=${snap['ttft_ms']} snap_eval=${snap['prompt_eval_tokens']} '
              'load_ms=$loadMs');
        }
      } catch (error, stack) {
        report['error'] = '$error';
        report['stack'] = '$stack'.split('\n').take(8).join('\n');
        _log('snapshot error $error');
      } finally {
        await _save('perf_snapshot', report);
        _log('snapshot report ${jsonEncode(report..removeWhere((k, v) => v is Map))}');
        await e.dispose();
      }
    });
  }, skip: _probe == 'threads', timeout: const Timeout(Duration(minutes: 15)));
}
