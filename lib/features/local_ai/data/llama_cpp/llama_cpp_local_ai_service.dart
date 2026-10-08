import 'dart:async';
import 'dart:io';

import 'package:llamadart/llamadart.dart';

import '../../../../core/error/app_exception.dart';
import '../../domain/context_window_policy.dart';
import '../../domain/local_ai_service.dart';
import '../stream_coalescer.dart';
import 'llm_metrics.dart';
import 'llm_model_config.dart';
import 'model_file_locator.dart';

/// [LocalAiService] backed by llama.cpp through the `llamadart` package.
///
/// - Inference runs in llamadart's worker isolate; the UI isolate only
///   receives text.
/// - The model is loaded once (lazily, on first use) and stays loaded for
///   the life of the service, across conversations.
/// - Cancelling a [generate] subscription sets llama.cpp's native abort flag,
///   so decoding stops instead of running on in the background.
///
/// No llamadart type leaves this file.
class LlamaCppLocalAiService implements LocalAiService {
  LlamaCppLocalAiService({
    this.config = LlmModelConfig.qwen35_2b,
    this._locator = const ModelFileLocator(),
    LlamaEngine Function()? createEngine,
  }) : _createEngine = createEngine ?? (() => LlamaEngine(LlamaBackend()));

  final LlmModelConfig config;
  final ModelFileLocator _locator;
  final LlamaEngine Function() _createEngine;

  /// After Stop, llama.cpp needs a moment to observe the abort flag; a new
  /// generation started in that window is retried rather than failed.
  static const Duration _busyRetryDelay = Duration(milliseconds: 50);
  static const int _busyRetryLimit = 100;

  late final ContextWindowPolicy _contextPolicy = ContextWindowPolicy(
    contextSize: config.contextSize,
    maxNewTokens: config.maxNewTokens,
  );

  late final GenerationParams _generationParams = GenerationParams(
    maxTokens: config.maxNewTokens,
    temp: config.temperature,
    topK: config.topK,
    topP: config.topP,
    minP: config.minP,
    penalty: 1.0,
    presencePenalty: config.presencePenalty,
    seed: config.seed,
    // Forward every token from the worker; StreamCoalescer limits UI
    // updates on the Dart side by time instead.
    streamBatchTokenThreshold: 1,
  );

  LlamaEngine? _engine;
  Future<void>? _loading;
  Future<void> _previousGeneration = Future<void>.value();
  bool _disposed = false;

  @override
  bool get isReady => _engine != null && !_disposed;

  @override
  Future<void> initialize() {
    if (_disposed) {
      return Future.error(const GenerationException('Service was disposed.'));
    }
    if (_engine != null) return Future.value();
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  Future<void> _load() async {
    final path = await _locator.find(config.fileName);
    if (path == null) {
      final expected = await _locator.candidatePaths(config.fileName);
      throw ModelUnavailableException(
        'Model ${config.fileName} is not installed. '
        'Expected at: ${expected.join(' or ')}',
      );
    }

    final engine = _createEngine();
    final stopwatch = Stopwatch()..start();
    try {
      await engine.loadModel(
        path,
        modelParams: ModelParams(
          contextSize: config.contextSize,
          gpuLayers: 0,
          preferredBackend: GpuBackend.cpu,
          numberOfThreads: config.threads,
          numberOfThreadsBatch: config.threads,
        ),
      );
    } catch (error) {
      await engine.dispose();
      throw GenerationException('The model could not be loaded.', error);
    }
    stopwatch.stop();

    if (_disposed) {
      await engine.dispose();
      return;
    }
    _engine = engine;
    LlmMetrics.log('model_loaded', {
      'model': config.displayName,
      'quant': config.quantization,
      'file_mib': File(path).lengthSync() >> 20,
      'n_ctx': await engine.getContextSize(),
      'threads': config.threads,
      'load_ms': stopwatch.elapsedMilliseconds,
      'rss_mib': LlmMetrics.residentMemoryMiB(),
    });
  }

  @override
  Stream<String> generate(GenerationRequest request) {
    final engine = _engine;
    if (engine == null || _disposed) {
      return Stream.error(const GenerationException('Model is not loaded.'));
    }

    late final StreamController<String> controller;
    // Cancelled in the controller's onCancel (and by cancelOnError).
    // ignore: cancel_subscriptions
    StreamSubscription<LlamaCompletionChunk>? subscription;
    var cancelled = false;
    // True once the native stream ended by itself. onCancel still fires when
    // the consumer's subscription is cleaned up after a normal close; it
    // must not abort anything then.
    var ended = false;
    final run = _RunStats();
    // Honour the request's cap, but never exceed the space the context
    // policy reserved for the reply.
    final maxTokens = request.maxTokens == null
        ? config.maxNewTokens
        : request.maxTokens!.clamp(1, config.maxNewTokens);
    final params = _generationParams.copyWith(maxTokens: maxTokens);

    final finished = Completer<void>();
    final previous = _previousGeneration;
    _previousGeneration = finished.future;
    void finish() {
      if (!finished.isCompleted) finished.complete();
    }

    final coalescer = StreamCoalescer(
      onEmit: (text) {
        if (!controller.isClosed) controller.add(text);
      },
    );

    Future<void> fail(Object error, [StackTrace? stackTrace]) async {
      ended = true;
      coalescer.flush();
      if (!controller.isClosed) {
        controller.addError(
          error is AppException
              ? error
              : GenerationException('Generation failed.', error),
          stackTrace,
        );
        await controller.close();
      }
      finish();
    }

    void listen(List<LlamaChatMessage> prompt, int attempt) {
      var receivedAny = false;
      subscription = engine
          .create(prompt, params: params, enableThinking: false)
          .listen(
        (chunk) {
          final text =
              chunk.choices.isEmpty ? null : chunk.choices.first.delta.content;
          if (text == null || text.isEmpty) return;
          if (!receivedAny) {
            receivedAny = true;
            run.markFirstToken();
          } else {
            run.markNextToken();
          }
          run.reply.write(text);
          coalescer.add(text);
        },
        onError: (Object error, StackTrace stackTrace) {
          final busy = !receivedAny &&
              error is StateError &&
              error.message.contains('already in progress');
          if (busy && !cancelled && attempt < _busyRetryLimit) {
            run.busyRetries++;
            Timer(_busyRetryDelay, () {
              if (cancelled) return finish();
              listen(prompt, attempt + 1);
            });
            return;
          }
          fail(error, stackTrace);
        },
        onDone: () {
          ended = true;
          coalescer.flush();
          unawaited(_logRun(engine, prompt, run, cancelled: false));
          controller.close();
          finish();
        },
        cancelOnError: true,
      );
    }

    Future<void> start() async {
      try {
        await previous;
        if (cancelled) return finish();
        final window = await _contextPolicy.fit(
          request.messages,
          engine.getTokenCount,
        );
        if (cancelled) return finish();
        listen(window.map(_toLlamaMessage).toList(), 0);
      } catch (error, stackTrace) {
        await fail(error, stackTrace);
      }
    }

    controller = StreamController<String>(
      onListen: () {
        run.start();
        unawaited(start());
      },
      onCancel: () async {
        if (ended) return;
        cancelled = true;
        coalescer.dispose();
        final active = subscription;
        if (active != null) {
          // Sets the native abort flag polled by llama.cpp's decode loop.
          engine.cancelGeneration();
          await active.cancel();
          unawaited(_logRun(engine, const [], run, cancelled: true));
        }
        finish();
      },
    );
    return controller.stream;
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    final engine = _engine;
    _engine = null;
    if (engine != null) {
      engine.cancelGeneration();
      await engine.dispose();
      LlmMetrics.log('model_released', {
        'rss_mib': LlmMetrics.residentMemoryMiB(),
      });
    }
  }

  Future<void> _logRun(
    LlamaEngine engine,
    List<LlamaChatMessage> prompt,
    _RunStats run, {
    required bool cancelled,
  }) async {
    if (!LlmMetrics.enabled) return;
    try {
      final totalMs = run.elapsedMs;
      final reply = run.reply.toString();
      final generated = reply.isEmpty ? 0 : await engine.getTokenCount(reply);
      final decodeMs = totalMs - (run.firstTokenMs ?? totalMs);
      final promptTokens = prompt.isEmpty
          ? null
          : (await engine.chatTemplate(prompt, enableThinking: false))
              .tokenCount;
      final perf = await engine.getPerformanceContext();
      LlmMetrics.log(cancelled ? 'generation_cancelled' : 'generation_done', {
        'prompt_msgs': prompt.isEmpty ? null : prompt.length,
        'prompt_tokens': promptTokens,
        'evaluated_prompt_tokens': perf?.promptEvalTokens,
        'gen_tokens': generated,
        'ttft_ms': run.firstTokenMs,
        'total_ms': totalMs,
        'tok_s': decodeMs > 0 && generated > 1
            ? ((generated - 1) * 1000 / decodeMs).toStringAsFixed(2)
            : null,
        'busy_retries': run.busyRetries,
        'threads': config.threads,
        ...run.gapStats(),
        'rss_mib': LlmMetrics.residentMemoryMiB(),
      });
    } catch (error) {
      LlmMetrics.log('metrics_failed', {'error': error});
    }
  }

  static LlamaChatMessage _toLlamaMessage(AiMessage message) =>
      LlamaChatMessage.fromText(
        role: switch (message.role) {
          AiRole.system => LlamaChatRole.system,
          AiRole.user => LlamaChatRole.user,
          AiRole.assistant => LlamaChatRole.assistant,
        },
        text: message.content,
      );
}

class _RunStats {
  final Stopwatch _clock = Stopwatch();
  final StringBuffer reply = StringBuffer();
  int? firstTokenMs;
  int busyRetries = 0;

  void start() => _clock.start();

  /// Milliseconds between consecutive text pieces from the worker (one per
  /// token, since the native batch threshold is 1), before UI coalescing.
  final List<int> _gapsMs = [];
  int _lastPieceMs = 0;

  void markFirstToken() {
    firstTokenMs ??= _clock.elapsedMilliseconds;
    _lastPieceMs = _clock.elapsedMilliseconds;
  }

  void markNextToken() {
    final now = _clock.elapsedMilliseconds;
    _gapsMs.add(now - _lastPieceMs);
    _lastPieceMs = now;
  }

  int get elapsedMs => _clock.elapsedMilliseconds;

  Map<String, Object?> gapStats() {
    if (_gapsMs.isEmpty) return const {};
    final sorted = [..._gapsMs]..sort();
    int at(double q) => sorted[((sorted.length - 1) * q).round()];
    return {
      'gap_p50_ms': at(0.5),
      'gap_p95_ms': at(0.95),
      'gap_max_ms': sorted.last,
      'stalls_over_2s': sorted.where((g) => g > 2000).length,
    };
  }
}
