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
    this.batchThreads = defaultAndroidBatchThreads,
    this.maxPromptTokens = defaultMaxPromptTokens,
    this.systemPromptSnapshot = true,
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

  /// Threads for prompt processing (prefill), which is compute-bound and
  /// scales differently from decoding.
  ///
  /// Measured 2026-10-09 on a Galaxy Tab S9 FE (Exynos 1380, 4× A78 +
  /// 4× A55), 220-token prompt, decode threads 2 (docs/LLM_PERFORMANCE.md):
  /// 2 → 28 tok/s, **4 → 60 tok/s**, 6 → 49 tok/s (slower: the A55s join
  /// and every layer waits for them), 8 → 61 tok/s. 4 gets nearly all of
  /// the gain on the big cores. Not yet re-measured on the Galaxy S10.
  static const int defaultAndroidBatchThreads = 4;

  /// Upper bound on prompt tokens (system + history + new message), below
  /// the `n_ctx − maxNewTokens` limit. Prompt processing is re-done every
  /// turn (no KV reuse for this hybrid model), so this bounds the worst
  /// time-to-first-token: ~1.3k conversation tokens ≈ 22 s at 60 tok/s.
  static const int defaultMaxPromptTokens = 1536;

  /// Qwen3.5-2B (Apache-2.0), 4-bit, from `unsloth/Qwen3.5-2B-GGUF`.
  ///
  /// Sampling uses the model card's lower-randomness non-thinking set:
  /// temperature 0.7, top_p 0.8, top_k 20, min_p 0, presence_penalty 1.5.
  ///
  /// The card's "non-thinking text" set (1.0 / 1.0 / 2.0) was used until
  /// 2026-10-08. On device it produced Chinese words inside Vietnamese
  /// answers (the card warns that a high presence penalty can cause
  /// language mixing) and misread a simple sum, so assistant answers now
  /// favour precision over variety. See docs/LLM_QUALITY.md.
  static const LlmModelConfig qwen35_2b = LlmModelConfig(
    displayName: 'Qwen3.5-2B',
    fileName: 'Qwen3.5-2B-Q4_K_M.gguf',
    quantization: 'Q4_K_M',
    contextSize: 4096,
    maxNewTokens: 1024,
    temperature: 0.7,
    topK: 20,
    topP: 0.8,
    minP: 0.0,
    presencePenalty: 1.5,
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

  /// CPU threads for decoding. Defaults to [defaultAndroidThreads].
  final int threads;

  /// CPU threads for prompt processing. Defaults to
  /// [defaultAndroidBatchThreads].
  final int batchThreads;

  /// See [defaultMaxPromptTokens].
  final int maxPromptTokens;

  /// Whether the processed system prompt is snapshotted once and restored
  /// per request instead of being re-evaluated (LlamaCppLocalAiService).
  final bool systemPromptSnapshot;

  /// Fixed sampler seed for reproducible benchmarks; null = time-based.
  final int? seed;

  /// Copy for benchmarks that vary one knob at a time.
  LlmModelConfig copyWith({
    int? threads,
    int? batchThreads,
    int? maxPromptTokens,
    bool? systemPromptSnapshot,
    double? temperature,
    double? topP,
    double? presencePenalty,
    int? seed,
  }) =>
      LlmModelConfig(
        displayName: displayName,
        fileName: fileName,
        quantization: quantization,
        contextSize: contextSize,
        maxNewTokens: maxNewTokens,
        temperature: temperature ?? this.temperature,
        topK: topK,
        topP: topP ?? this.topP,
        minP: minP,
        presencePenalty: presencePenalty ?? this.presencePenalty,
        threads: threads ?? this.threads,
        batchThreads: batchThreads ?? this.batchThreads,
        maxPromptTokens: maxPromptTokens ?? this.maxPromptTokens,
        systemPromptSnapshot: systemPromptSnapshot ?? this.systemPromptSnapshot,
        seed: seed ?? this.seed,
      );
}
