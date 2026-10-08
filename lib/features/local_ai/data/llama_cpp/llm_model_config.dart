/// Runtime configuration for one GGUF model. Everything model-specific lives
/// here so switching models for a benchmark is a one-object change.
class LlmModelConfig {
  const LlmModelConfig({
    required this.displayName,
    required this.fileName,
    required this.quantization,
    required this.contextSize,
    required this.maxNewTokens,
    required this.temperature,
    required this.topK,
    required this.topP,
    required this.minP,
    required this.presencePenalty,
    this.threads = defaultAndroidThreads,
    this.seed,
  });

  /// Decode threads used on Android (the only platform running llama.cpp in
  /// this phase).
  ///
  /// Validated on ONE device, a Samsung Galaxy S10 (Exynos 9820: 2 big +
  /// 2 mid + 4 little cores): 2 threads gave the best and most stable
  /// throughput (~8.8 tok/s, p95 token gap < 140 ms, no stalls). 4 threads
  /// caused the scheduler to pack two decode threads onto one core, stalling
  /// ggml's per-layer barrier (gaps up to 8.5 s, 1.8 tok/s). 3 threads was
  /// stable but ~12% slower. See docs/LLM_BENCHMARK.md.
  ///
  /// This is a validated default for that device class, not a universal
  /// optimum; other SoCs should be re-measured with
  /// `integration_test/thread_sweep_test.dart` (`--dart-define=LLM_THREADS=N`).
  static const int defaultAndroidThreads = 2;

  /// Qwen3.5-2B (Apache-2.0), 4-bit, from `unsloth/Qwen3.5-2B-GGUF`.
  ///
  /// Sampling follows the official model card for non-thinking text tasks:
  /// temperature 1.0, top_p 1.0, top_k 20, min_p 0, presence_penalty 2.0.
  static const LlmModelConfig qwen35_2b = LlmModelConfig(
    displayName: 'Qwen3.5-2B',
    fileName: 'Qwen3.5-2B-Q4_K_M.gguf',
    quantization: 'Q4_K_M',
    contextSize: 4096,
    maxNewTokens: 1024,
    temperature: 1.0,
    topK: 20,
    topP: 1.0,
    minP: 0.0,
    presencePenalty: 2.0,
  );

  final String displayName;
  final String fileName;
  final String quantization;

  /// `n_ctx`. Conservative for phones; the model supports far more.
  final int contextSize;

  /// Upper bound on generated tokens per reply.
  final int maxNewTokens;

  final double temperature;
  final int topK;
  final double topP;
  final double minP;
  final double presencePenalty;

  /// CPU threads for decoding and prompt processing. Defaults to
  /// [defaultAndroidThreads].
  final int threads;

  /// Fixed sampler seed for reproducible benchmarks; null = time-based.
  final int? seed;

  /// Copy for benchmarks that vary one knob at a time.
  LlmModelConfig copyWith({int? threads, int? seed}) => LlmModelConfig(
        displayName: displayName,
        fileName: fileName,
        quantization: quantization,
        contextSize: contextSize,
        maxNewTokens: maxNewTokens,
        temperature: temperature,
        topK: topK,
        topP: topP,
        minP: minP,
        presencePenalty: presencePenalty,
        threads: threads ?? this.threads,
        seed: seed ?? this.seed,
      );
}
