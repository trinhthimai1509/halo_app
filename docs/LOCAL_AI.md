# Local AI

Phase 2 status: a **real on-device LLM runs on Android**, validated on a
Samsung Galaxy S10. iOS has no on-device runtime yet (it reports "not
available"). Offline speech-to-text is documented in [SPEECH.md](SPEECH.md). Measured results are in [LLM_BENCHMARK.md](LLM_BENCHMARK.md).

## 1. Runtime

| | |
|---|---|
| Engine | [llama.cpp](https://github.com/ggml-org/llama.cpp) (GGUF), CPU backend |
| Flutter binding | [`llamadart`](https://pub.dev/packages/llamadart) **0.8.24**, pinned exactly (MIT, verified publisher `leehack.com`) |
| Native binaries | `leehack/llamadart-native` **v0.4.1** (llama.cpp built Sept 2026), downloaded by llamadart's build hook **at build time** |
| Integration | Dart FFI, run in llamadart's own worker `Isolate`. No MethodChannel, and no Kotlin/Java code of ours |
| Android ABIs | `arm64-v8a` (phones) and `x86_64` (emulator), set with `abiFilters` in `android/app/build.gradle.kts` |

### Why llamadart
I checked this in the package source, not just the README:
- **Threading:** inference runs in a dedicated worker isolate.
- **Cancellation:** `cancelGeneration()` sets a native flag that llama.cpp's decode loop polls.
- **UTF-8 safety:** tokens are batched as bytes, so Vietnamese multi-byte characters are never split.
- **Chat template:** it applies the GGUF's embedded Jinja chat template (`tokenizer.chat_template`).
- **Metrics:** it exposes token counting and native performance counters.

**Alternatives considered:**
- `llm_llamacpp`: similar design, but an unverified uploader and very little adoption.
- Our own FFI over llama.cpp's official Android arm64 prebuilt binaries: the most control, but it would re-implement the sampler loop, templates, UTF-8 handling and isolate plumbing. This is the fallback if llamadart stalls.
- MediaPipe/LiteRT (`flutter_gemma`): not GGUF, and the Gemma licence isn't Apache.
- MLC-LLM and ExecuTorch: much heavier native integration.

### Build configuration (`pubspec.yaml` → `hooks.user_defines.llamadart`)
- `llamadart_native_runtimes: [llama_cpp]`: bundles llama.cpp only. The default also bundles LiteRT-LM, about 55 MB per ABI.
- `llamadart_native_backends: cpu` on android-arm64, android-x64 and windows-x64: no Vulkan, which would otherwise add about 40 MB including a 14.5 MB validation layer. GPU offload is a later experiment.
- The arm64 bundle ships several ggml CPU variants (armv8.0 through armv9.2) and picks one at runtime from the CPU's features.

### Dependency and network notes
- llamadart depends on the `http` package, which it uses only for its optional `loadModelFromUrl`. We only call `loadModel(path)`.
- The **release** manifest has **no INTERNET permission**; only debug and profile builds get it, for Flutter tooling. So the release app physically cannot open a network connection.
- Builds need the network the first time, to fetch native bundles into the **pub cache** (`…/Pub/Cache/hosted/pub.dev/llamadart-0.8.24/.dart_tool/llamadart/`). That cache survives `flutter clean`.
- **Windows host caveat:** `flutter test` runs the build hook for the host, which downloads `llamadart-native-windows-x64-v0.4.1.tar.gz` (**734 MB**, because it includes CUDA and Vulkan) once. The unit tests never load it. macOS and Linux host bundles are 4.5 MB and 177 MB.

## 2. Model

| | |
|---|---|
| Model | **Qwen3.5-2B** (instruct, non-thinking by default), released March 2026 |
| File | `Qwen3.5-2B-Q4_K_M.gguf` |
| Quantisation | Q4_K_M (4-bit) |
| Size | 1,280,835,840 bytes (1.19 GiB) |
| SHA-256 | `aaf42c8b7c3cab2bf3d69c355048d4a0ee9973d48f16c731c0520ee914699223` |
| Source | <https://huggingface.co/unsloth/Qwen3.5-2B-GGUF> (a quantisation of [Qwen/Qwen3.5-2B](https://huggingface.co/Qwen/Qwen3.5-2B); Qwen publishes no official GGUF for this size) |
| Licence | **Apache-2.0**, commercial use allowed |
| Languages | 201 per the model card, including Vietnamese |
| Architecture | Hybrid Gated DeltaNet plus gated attention, 24 layers, with a vision encoder that isn't loaded (no mmproj) |

Model binaries are **never committed**: `.gitignore` excludes `*.gguf`, `*.litertlm` and `/models/`.

## 3. Development setup: installing the model on Android

> **Customers** import the model inside the app; see [MODEL_INSTALL.md](MODEL_INSTALL.md). The ADB steps below are a developer shortcut. An imported model (app-private storage) takes precedence over an ADB copy.

```bash
# 1. Download to the host (outside the repo) and verify
curl -L -o C:/dev/models/Qwen3.5-2B-Q4_K_M.gguf https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/main/Qwen3.5-2B-Q4_K_M.gguf
sha256sum C:/dev/models/Qwen3.5-2B-Q4_K_M.gguf

# 2. Install the app once (this creates its external files folder), then push
adb shell mkdir -p /sdcard/Android/data/dev.offlineai.offline_ai_chat/files/models
adb push C:/dev/models/Qwen3.5-2B-Q4_K_M.gguf /sdcard/Android/data/dev.offlineai.offline_ai_chat/files/models/
# 3. Android 11+ (verified on Android 16): a folder created by `adb shell` is
#    owned by `shell` (mode 2770) and the app cannot read it. Open it up:
adb shell chmod -R a+rwX /sdcard/Android/data/dev.offlineai.offline_ai_chat/files/models
```

- With several devices attached, add `-s <serial>` to every command.
- The push takes about 45 s over USB 3.
- No storage permission is needed.

**How the app finds the model** (`ModelFileLocator`) is the first existing path in this list:
1. `getExternalStorageDirectory()/models/<file>`, which is `/sdcard/Android/data/<pkg>/files/models/`. This is where development builds get the model.
2. `getApplicationSupportDirectory()/models/<file>`, the internal location a future first-run install would use.

If neither exists, the chat shows *"The on-device model is not installed."* The user's message is still saved.

> ⚠️ **Uninstalling the app deletes the model.** Android removes
> `Android/data/<pkg>/` on uninstall, so re-push after any reinstall.
> `flutter test` on a device **uninstalls the app after a successful run**,
> so always pass `--no-uninstall` to integration tests.

Production distribution (bundled with the app or downloaded on first run) is **not decided yet**. Inference is offline either way.

## 4. Integration architecture

```
ChatController (presentation)
   │  SendMessage use case (domain): adds the system prompt, persists the turns
   ▼
LocalAiService (interface, local_ai/domain)
   ▲
LlamaCppLocalAiService (local_ai/data/llama_cpp) ── only file importing llamadart
   ├─ ModelFileLocator       where the GGUF lives
   ├─ ContextWindowPolicy    what fits in n_ctx (domain, pure Dart, unit-tested)
   ├─ StreamCoalescer        ≤ 1 UI update per 50 ms (unit-tested)
   └─ LlmMetrics             `[LLM]` log lines (development only)
```

- `lib/app/di/providers.dart` picks the implementation: `LlamaCppLocalAiService` on Android and `UnsupportedLocalAiService` elsewhere. The latter fails with a clear message; production code has no fake path.
- Unit and widget tests inject `FakeLocalAiService` from `test/fakes/`.
- No domain or presentation file imports llamadart. `ModelUnavailableException` (in `core/error`) is the only new error type the UI knows about.

### Prompt and chat template
- The prompt is built from the GGUF's own Jinja template, which for Qwen3.5 is ChatML-style. It is called with `enableThinking: false`; llamadart's own default is `true`, which would emit a hidden reasoning block.
- **System prompt** (`AssistantInstructions.systemPrompt(now)`):
  - Vietnamese, carrying the device's current **date**. It has no clock time, so it stays identical all day.
  - Short rules: answer in the user's language, concisely; "tôi" means the user; don't invent; say "không biết" for live data or uncertain facts; ask for clarification on unclear (possibly mis-transcribed) input; no Markdown.
  - About 200 tokens. It is processed **once per day** and restored from a snapshot for each request (§ Prompt processing below).
- **Calendar questions** ("hôm nay là thứ mấy?" and similar) are answered in Dart from the device clock (`CalendarAnswers`), and **explicit simple calculations** ("17 cộng 25") exactly by `ArithmeticAnswers`. Neither reaches the model.
- **Prompt processing** (since 2026-10-09; [LLM_PERFORMANCE.md](LLM_PERFORMANCE.md)):
  - prefill runs on 4 threads (`batchThreads`), decode on 2;
  - the processed system prompt is snapshotted with `llama_state_save_file` and restored per request, used only after a normally completed generation;
  - prompts are capped at 1,536 tokens (`maxPromptTokens`).
  - Median time to first token on the Tab S9 FE: 0.93 s, previously 8.3 s.
- Message order: system → trimmed history → current user turn → assistant generation.
- **Sampling** uses the model card's lower-randomness non-thinking set: temperature 0.7, top_p 0.8, top_k 20, min_p 0, presence_penalty 1.5, repeat penalty 1.0.
  - The card's other set (1.0 / 1.0 / 2.0) was used until 2026-10-08. It produced language mixing and invented facts on device; see [LLM_QUALITY.md](LLM_QUALITY.md).

### Context policy (`ContextWindowPolicy`)
- `n_ctx` = **4096**. The reply reserve is `maxNewTokens` = **1024**, plus a 64-token safety margin, leaving at most 3008 tokens. Since 2026-10-09 the prompt is **capped at 1536 tokens** (`maxPromptTokens`) to bound time to first token.
- Each message is costed with the model's tokenizer plus 8 tokens of template overhead.
- Leading system messages and the current user turn are always kept.
- Older turns are added from newest to oldest while they fit.
- The kept history never starts with an assistant turn.
- If the current message alone exceeds the budget, generation fails with a `GenerationException`.
- The full SQLite history is passed in; the policy decides what reaches the model.

### Streaming
- The native batching threshold is 1, so each token is forwarded from the worker isolate.
- `StreamCoalescer` emits the first piece immediately, then at most once every 50 ms, so fast models don't cause a rebuild per token.
- On the S10 at about 9 tok/s, each UI update carries roughly one token.
- The existing UI streaming (caret, bubble growth) is unchanged.

### `maxTokens`
`GenerationRequest.maxTokens`, if set, caps the reply at `min(maxTokens, config.maxNewTokens)`. *(Fixed in Phase 2: the field existed but was ignored.)*

### Cancellation (Stop)
1. The UI's Stop cancels the `SendMessage` stream subscription.
2. That cancels the service's `generate` stream.
3. In `onCancel`, `engine.cancelGeneration()` sets the native abort flag, and cancelling the llamadart subscription detaches the Dart side.
4. llama.cpp's decode loop sees the flag within one token and exits.

The partial reply is persisted by `SendMessage`'s `finally` block, so history matches what was shown.

- **Measured on the S10:**
  - process CPU dropped from 2.2–3.9 busy cores to about 0.13 within 1 s of Stop;
  - no text arrived after Stop;
  - the next request started in about 1.2 s.
- **Busy window:** after Stop, llama.cpp needs a moment to observe the flag, and llamadart rejects a new generation in that window ("already in progress"). The service waits for the previous generation and retries a busy start every 50 ms, up to 100 times.
- **`onCancel` fix (Phase 2):** `StreamController.onCancel` also fires when a consumer's subscription is cleaned up after a *normal* completion. It used to call `cancelGeneration()` then, which is harmless on its own but could abort a generation that had just started. An `ended` flag now makes `onCancel` a no-op after normal completion or an error. This was verified in every later run: no spurious `generation_cancelled` lines.

### Threading
- Decoding and prompt processing run on llama.cpp's native threads, driven from llamadart's worker isolate. The UI isolate only receives text.
- **Default: 2 threads on Android** (`LlmModelConfig.defaultAndroidThreads`).
  - This is **validated on the Galaxy S10 (Exynos 9820), not a universal optimum.**
  - With 4 threads, Android's scheduler packed two decode threads onto one core in about 60 % of samples. Because ggml synchronises all threads after every layer, that caused gaps of up to 8.5 s and speeds as low as 1.8 tok/s.
  - With 2 threads, the threads run on the two big cores at about 8.8 tok/s with no stalls.
  - Re-measure on other SoCs with `integration_test/thread_sweep_test.dart --dart-define=LLM_THREADS=N` (see LLM_BENCHMARK.md).

### Lifecycle and memory
- **Load:** lazily, on the first generation (`SendMessage` calls `initialize()`). There's no preloading at app start, so no memory is spent if the user never chats. The first reply waits for the load (about 4.5–6 s on the S10) while the thinking indicator shows.
- **Stays loaded** for the life of the provider, meaning the app process, across conversations. It's never reloaded per message, and concurrent `initialize()` calls share one load.
- **Memory:** weights are memory-mapped (`useMmap`), which gives file-backed, clean pages. Resident memory after load is about 2.9 GB, including the mapped model and the Flutter debug runtime; it falls to about 0.45 GB after `dispose()`.
- **Background:** the model is kept loaded. Mapped weights are reclaimable by the OS, so no unload on pause is implemented. If Android kills the process, the next message reloads the model lazily. An in-flight generation continues in the background up to its token cap; Samsung may freeze a backgrounded app, which pauses it. See the regression results in LLM_BENCHMARK.md.
- **Dispose:** `ref.onDispose` → `dispose()` cancels any generation and frees the model and context.

### Benchmark instrumentation (development only)
`LlmMetrics` writes one `[LLM]` line per event to logcat:
- `model_loaded`: load ms, `n_ctx`, threads, RSS.
- `generation_done` and `generation_cancelled`: prompt and generated tokens, TTFT, total ms, tok/s, token-gap p50/p95/max, stalls over 2 s, RSS.

Logging is on in debug and profile builds, and in release only with `--dart-define=LLM_METRICS=true`. Nothing is stored or sent anywhere.

## 5. Current limitations
- One device validated (Galaxy S10, 8 GB). Low-RAM devices (≤ 4 GB) and other SoCs are untested.
- CPU only; Vulkan/GPU offload hasn't been tried.
- No model provisioning UX: the model is installed with `adb` for development.
- The Windows host needs the 734 MB llamadart bundle for `flutter test`.
- Replies are plain text (no markdown rendering); the model often emits markdown.
- The model sometimes produces weak Vietnamese output: a non-email reply to the email prompt, and name slips ("Mái"). See LLM_BENCHMARK.md.
- `armeabi-v7a` (32-bit) devices aren't supported, because there are no native libraries for them.

## 6. Future iOS integration (not started)
- The same Dart code applies. llamadart ships an iOS SwiftPM companion (`llamadart_llama_cpp_flutter`, iOS ≥ 16.4) with Metal support.
- Model location: `getApplicationSupportDirectory()/models/`, which is already the second candidate path.
- `providers.dart` currently returns `UnsupportedLocalAiService` on iOS; switch it after validating on a device.
- Re-run the thread sweep on Apple silicon; the right thread count will differ.
- Needs a Mac with Xcode. This project has only been built on Windows so far.

## 7. Speech-to-text
Integrated on Android with sherpa-onnx. See [SPEECH.md](SPEECH.md). STT and the LLM never decode at the same time (the 🎤 is disabled while a reply is generating).
