# LLM benchmark: Qwen3.5-2B Q4_K_M on Android

All measurements were taken on **one physical device**. Treat the numbers as
indicative for similar phones, not as universal.

## Test device

| | |
|---|---|
| Device | Samsung Galaxy S10 (SM-G973F), Android 12 (API 31) |
| SoC | Exynos 9820: 2× Mongoose M4 @ 2.73 GHz + 2× Cortex-A75 @ 2.31 GHz + 4× Cortex-A55 @ 1.95 GHz |
| CPU features | `asimddp` (dot product), no i8mm → ggml picks an armv8.2 CPU variant |
| RAM | 7.2 GiB total (about 3.8 GiB available at idle) |
| ABI | arm64-v8a |
| Power | USB-powered at 100 % battery. The screen stayed on throughout. |

**Model:** `Qwen3.5-2B-Q4_K_M.gguf`, 1,280,835,840 bytes, from `unsloth/Qwen3.5-2B-GGUF`, Apache-2.0.
**Runtime:** llamadart 0.8.24 with llamadart-native v0.4.1 (llama.cpp), CPU only.
**Settings:** `n_ctx` 4096 · `maxNewTokens` 1024 · temperature 1.0 · top_p 1.0 · top_k 20 · min_p 0 · presence penalty 2.0 · thinking off.

## Method

- **Tools:**
  - `integration_test/llm_benchmark_test.dart`: the 7-prompt set plus a Stop case.
  - `integration_test/thread_sweep_test.dart`: the controlled thread comparison.
  - `integration_test/regression_test.dart`: regression cases A–C.
- Run them with `flutter test <file> -d <serial> --no-uninstall`. Without `--no-uninstall`, the app is uninstalled after the run, which deletes the pushed model.
- The service logs one `[LLM]` line per event, covering load time, prompt and generated tokens, TTFT, total time, tok/s, token-gap p50/p95/max, stalls over 2 s and resident memory.
- **Decode tok/s** = (generated tokens − 1) / (total − TTFT).
- **Token gap** = the interval between successive tokens from the worker, measured before UI coalescing.
- A host script (`tool/thread_sweep.sh` for the sweep, `tool/regression_monitor.sh` for the regression) sampled the following every 2–3 s:
  - per-core current and maximum frequency (the "cap");
  - the SoC's AP temperature;
  - per-thread CPU usage and core, via `top -H`.

  It also sent a no-op key press every 60 s to keep the screen on, and aborts the run if AP reaches 75 °C.
- Raw logs are in [`docs/benchmark_logs/`](benchmark_logs/).
- Integration tests run in **debug** mode, which uses the Dart JIT. Inference is native, so decode speed isn't affected; release-build figures from the UI smoke test match.

## 1. First full runs (4 threads): the problem

These runs are in `benchmark_logs/run2_threads4.log`, `run3_threads4.log` and `run3_threads4_monitor.log`.

| Case | Tokens | TTFT | Total | tok/s |
|---|---|---|---|---|
| vi_greeting | 178–191 | 1.8 s | 39–72 s | 2.5–5.1 |
| vi_explain_ai | 317–476 | 1.4–1.7 s | 57–87 s | 5.5–5.7 |
| vi_email | 45 / **522** | 1.4–1.7 s | 7 s / **954 s** | 7.6 / **0.55** |
| vi_memory (2 turns) | 58 + 66 | 1.4 / 4.4 s | 34 + 47 s | 1.5–1.8 |
| vi_breakfast | 421 | 1.8 s | **299 s** | 1.41 |
| en_ram_storage | 896 | 1.7 s | **774 s** | 1.16 |

- Throughput was erratic and at times collapsed to about 1 tok/s. The 954-second outlier happened with the screen on and the app in the foreground.
- `top -H` showed **two of the four decode threads sharing one core** while another fast core sat idle.
- ggml synchronises all threads after every layer, so a thread that only gets half a core stalls every token.
- Samsung also held the big cores at 1378 MHz (50 % of maximum) from about 2 minutes of sustained load onward, with AP only 48–52 °C.

## 2. Controlled thread comparison (2 vs 3 vs 4)

Logs: `benchmark_logs/thread_sweep/`.

**Protocol:**
- Identical model, `n_ctx`, sampling, **seed 42** and prompts; only `--dart-define=LLM_THREADS` changes.
- Force-stop the app and cool down until AP ≤ 45 °C before each configuration.
- Cases:
  - short: 64-token cap;
  - medium: "Giải thích trí tuệ nhân tạo…", 256-token cap, ending naturally at 208 tokens;
  - Stop: stop after about 48 tokens, then an immediate "Say ok".
- Stall guard: abort if one gap exceeds 10 s, or if speed after 32 tokens is under 0.5 tok/s.
- Each configuration was run twice, the second time as a medium-case repeat with a corrected, CPU-sorted thread sampler.
- The fixed seed produced **byte-identical replies** in all three configurations.

| Metric | **2 threads** | 3 threads | 4 threads |
|---|---|---|---|
| Model load time | 4.4–6.1 s | 4.6–4.8 s | 4.5–6.0 s |
| TTFT, short / medium / repeat | 2.0 / 1.6 / 2.4 s | 1.8 / 1.7 / 2.1 s | 2.1 / 1.4 / 3.0 s |
| tok/s, short | **9.39** | 7.52 | 7.59 |
| tok/s, medium (run 1 / run 2) | **8.81 / 8.83** | 7.41 / 7.80 | 6.87 / **1.83** |
| Medium total time | 25.1 / 25.8 s | 29.6 / 28.7 s | 31.5 / **116.1 s** |
| Token gap p95, medium | **137–139 ms** | 153–215 ms | 338 / **2458 ms** |
| Token gap maximum, all cases | **267 ms** | 340 ms | **8510 ms** |
| Gaps over 2 s | **0** | 0 | **19** |
| Resident memory, peak | 2.96 GB | 2.96 GB | 2.97 GB |
| Two threads on one core (% of samples) | **0 %** | 9 % | **60 %** |
| Big-core actual clock, average | 1.9–2.0 GHz (near the cap) | 1.6–1.9 GHz | 1.4–1.8 GHz (cap averaged 2.5 GHz) |
| Stop: cores busy before → after | 2.16 → 0.15 | 3.14 → 0.12 | 3.93 → 0.13 |
| Next generation after Stop | 1.27 s | 1.24 s | 5.89 s |

**Result: 2 threads** is now the Android default (`LlmModelConfig.defaultAndroidThreads`).
- It has the best and most repeatable decode speed, the tightest token gaps, and no stalls.
- Its two threads sit on the two big cores.
- 4 threads is *pathological*: the stalls came from thread packing even when the chip was cool and the caps were high.
- 3 threads is stable but about 12 % slower.
- The trade-off: 2 threads keeps the big cores fully loaded, so the chip warms more quickly (to about 62 °C in 25 s).

> ⚠️ This is validated on the Exynos 9820 only. Re-run `thread_sweep_test.dart`
> on other SoCs; the right count depends on the core layout and the scheduler.

## 3. Final regression (2 threads)

Logs: `benchmark_logs/regression/`.

### A–C: integration test (`regression_test.dart`), 4 of 4 passed

| Case | Result |
|---|---|
| **A.** Normal completion → immediate next | Both completed. Second reply: 64 tokens at 8.87 tok/s, busy retries 0. |
| **B.** Stop → immediate next | Cores busy 2.19 → **0.12** within 1 s. No text after Stop. The next request ran to its cap (48 of 48 tokens, 9.53 tok/s), so no stale cancellation. |
| **C1.** 5 consecutive generations | All ok, 77–96 tokens each, 8.4–8.8 tok/s, p95 gap ≤ 139 ms, no stalls. |
| **C2.** Sustained generation, 3-minute budget | 5 runs and 917 tokens in 194 s. No stalls; maximum gap 323 ms. |

**Sustained-load behaviour (C2):**

| Run | Tokens | tok/s | Gap p50 / p95 | Cumulative time | AP temperature |
|---|---|---|---|---|---|
| 1 | 254 | 8.53 | 115 / 123 ms | 0.5 min | about 60 °C |
| 2 | 256 | 5.77 | 184 / 193 ms | 1.3 min | 62–63 °C |
| 3 | 101 | 3.88 | 264 / 267 ms | 1.8 min | 56–60 °C |
| 4 | 48 | 3.70 | 264 / 266 ms | 2.1 min | about 52 °C |
| 5 | 256 | 3.86 | 265 / 267 ms | 3.2 min | about 49 °C |

- After about 1.5 minutes of continuous generation, the big cores were held at **1378 MHz**. That was below their reported caps (2.47–2.6 GHz), and it persisted even as the chip cooled to 49 °C. This looks like a Samsung sustained-performance power policy.
- Throughput settles at about **3.9 tok/s**, with perfectly even gaps (p95 ≈ p50) and **no stalls**. It degrades gracefully instead of stalling.
- Normal chat use, meaning short bursts with pauses, stays in the fast (8–9 tok/s) regime.
- The 75 °C safety limit was never reached (peak AP 63 °C).

### UI smoke test: release APK (arm64, `--dart-define=LLM_METRICS=true`)

| Check | Result |
|---|---|
| Model load on first message | 4.3 s |
| Suggestion chip → streamed reply | 216 tokens, TTFT 1.9 s, 9.17 tok/s, maximum gap 176 ms |
| Multi-turn context delivered to the model | `prompt_msgs` grows each turn (6, then 10, then 12); history reaches the model |
| Model recalls the name (English, UI) | **FAIL (model quality):** "Your name isn't revealed yet". The same test in Vietnamese passed. |
| Stop button | Process CPU 307 % → **0 %** within 1.5 s; partial reply kept |
| Message right after Stop | Answered normally |
| Background 60 s → resume → generate | Same PID; the model was **not** reloaded; generation succeeded |
| Force-stop → relaunch | Conversation present in History |

### Prompt processing (time to first token) grows with history
Measured in the UI. `evaluated_prompt_tokens` always equalled the **full** prompt, meaning llama.cpp did **not** reuse the previous turn's KV cache, even with `reusePromptPrefix` enabled.

| Prompt tokens | 42–52 | 279 | 305 | 409 | 460 |
|---|---|---|---|---|---|
| TTFT | 1.4–2.4 s | 8.4 s | 9.0 s | 12.5 s | 13.5 s |

- Prompt processing runs at about 34 tokens/s, so a conversation near the 3000-token budget would wait about 90 s for its first token.
- The likely cause is Qwen3.5's recurrent (Gated DeltaNet) layers, whose state can't be rolled back to a shared prefix. This is **not yet confirmed**.
- It's the most important performance limitation found.

## 4. Quality observations (not a scientific evaluation)

**Vietnamese:**
- Replies are fluent and on topic for greetings, explaining AI simply, and breakfast ideas.
- The email prompt got a 1-line non-email answer once ("Bảy nhé 😃…"), and a proper email in another run.
- In one turn the model misspelled the name as "Mái".
- It recalled "Mai" correctly in the Vietnamese multi-turn test.

**English:** good explanations (RAM vs storage, Clean Architecture, on-device AI). It failed to recall the name in one UI run.

**General:**
- It introduces itself as "Qwen3.5 … Alibaba Cloud"; the system prompt is intentionally neutral.
- It often emits markdown (`**bold**`, lists), which the UI shows as raw text.
- Temperature 1.0 (the model card's recommendation) produces variable answers. A lower temperature may help reliability; this is untested.

## 5. Limitations of this benchmark
- One device, one model, one quantisation. CPU only; Vulkan wasn't tried.
- The phone was USB-powered at 100 % battery. Battery drain and battery-powered thermals weren't measured.
- Most cases are short. The longest sustained test was 3.2 minutes, a deliberately bounded run.
- Thread placement comes from 2–3 s `top` snapshots, which is indicative rather than a full trace.
- Integration tests ran debug builds; the release build was checked only through the UI smoke test.
- The first 3- and 4-thread attempts failed because the app was uninstalled and the model deleted (`failed_*_model_missing.log`). They were re-run under the same protocol.
- The first sweep monitor sorted `top` output by the wrong column, so its per-thread samples are unusable. Placement figures come only from the `*_placement` runs.
