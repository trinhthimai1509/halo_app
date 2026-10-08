# LLM response time: recovery (2026-10-09)

**Device:** Galaxy Tab S9 FE (SM-X510, Exynos 1380: 4× Cortex-A78 + 4× Cortex-A55, Android 16).
**Model:** Qwen3.5-2B Q4_K_M with llama.cpp via llamadart 0.8.24. The model is unchanged.

**Baseline:** commit `366ae73`. **Candidate:** this change.

**Evidence:** [test_evidence/llm_performance_2026-10-09/](test_evidence/llm_performance_2026-10-09/).
**Reproduce:**
- `integration_test/perf_probe_test.dart`
- `integration_test/quality_eval_test.dart` (`QE_PARTS=after,consistency,recovery,seeds`)

## 1. Why the system prompt cost about 7 s

| Factor | Measured |
|---|---|
| System prompt | 38 → ~220 tokens (date and time plus rules, 366ae73) |
| Prompt processing (prefill), 2 threads | **27.5 tok/s**, so 220 tokens take 7.8–8.1 s. That is almost the entire time to first token |
| Decode | 7–9 tok/s, unaffected |
| Repeated work | **Yes.** Every request re-processed the whole prompt: system + history + message |
| KV/prefix reuse | Not effective. llamadart's `reusePromptPrefix` (on by default) keeps the shared prefix and calls `llama_memory_seq_rm` to drop the rest. Qwen3.5 is a **hybrid model with recurrent (Gated DeltaNet) layers**, whose state cannot be partially rolled back, so the call fails and llamadart re-processes everything (`evaluated_prompt_tokens` always equalled the full prompt) |
| Prompt stability | The prompt also contained the clock time (HH:MM), so it changed every minute; that would defeat any cache |

## 2. Experiments (one change at a time)

### E1: prefill threads (decode stays at 2, validated for decode)

| `n_threads_batch` | Prefill (220-token prompt) | Short-question TTFT | 1,202-token history TTFT | Decode |
|---|---|---|---|---|
| 2 (baseline) | 27.3–28.4 tok/s | 7.8–8.1 s | 45.1 s | 7.5–8.5 tok/s |
| **4** | **58.8–60.7 tok/s** | **3.6–3.8 s** | 23.9 s | 9.1–9.5 tok/s |
| 6 | 48.7–49.7 tok/s (**slower than 4**) | 4.4–4.6 s | 25.9 s | 8.8–9.3 tok/s |
| 8 | 60.3–62.0 tok/s | 3.6–3.7 s | 20.1 s | 8.6–8.9 tok/s |

More threads isn't automatically faster: 6 is slower than 4, probably because the A55 cores join and every layer waits for them. **4 was chosen.** It gets almost all of the gain while staying on the big cores. It has **not** been re-measured on the Galaxy S10 (2 big + 2 mid cores).

### E2: system-prompt state snapshot

**Mechanism:**
- Process the system block once with `generate(prefix, maxTokens: 0)`. Nothing is sampled, so the state holds exactly the prefix.
- Save it with `stateSaveFile`.
- Per request, restore it with `stateLoadFile` and enable prefix reuse. llamadart then removes an empty range, which is valid even for recurrent state, and evaluates only the conversation.

| | Without snapshot | With snapshot |
|---|---|---|
| q1: tokens evaluated / TTFT | 220 / 7.9 s | **23 / 1.05 s**, output **byte-identical** (seed 42) |
| q2 | 223 / 8.5 s | 26 / 1.1 s, byte-identical |
| multi-turn | 241 / 9.1 s | 44 / 1.7 s. Same answer; the last two words differ (floating-point differences from a different batch split) |
| Restore time | — | 19–61 ms |
| Build (once per system prompt, i.e. per day) | — | 3.4–4.0 s with 4 threads |
| File | — | 22.7 MB in the app cache dir |

**Safety rules in `LlamaCppLocalAiService`:**
- The snapshot is used only if the **previous generation ended normally**. After Stop, llama.cpp may still be finishing a decode, and the restore has no guard in llamadart.
- It is used only if the rendered prompt **starts with the exact snapshotted text**.
- Any failure falls back to full processing, which clears memory first.
- A busy retry never reuses restored state.

### E3: fewer prompt and history tokens
- **The clock time was removed from the system prompt**, so the prompt is identical all day and the snapshot stays valid. Time questions were already answered in Dart (`CalendarAnswers`).
- **The prompt budget is capped at 1,536 tokens** (`maxPromptTokens`; it was effectively 3,008). The worst case (J2) went from 113 s to 29 s. The trade-off: in very long chats, turns older than about 1.3k tokens are no longer seen by the model.

### Not changed
Sampling stays at temperature 0.7 / top_p 0.8 / presence 1.5. The quality runs below show that answer variance across seeds is large anyway, so there was no quality reason to change it.

## 3. Reliability fixes
- **Arithmetic:** `ArithmeticAnswers` handles explicit 2–4 operand calculations (+ − × ÷, the words cộng / trừ / nhân / chia, and Vietnamese number notation) exactly in Dart.
  - It uses a fixed grammar. There's no `eval` and no code execution.
  - Word problems still go to the model.
  - Result: D1 and J3 pass 6/6, versus 3/6 by the model at baseline ("17 + 25 = 32").
- **Previous-turn recall:** a prompt line says that "tôi" means the user. G1 and G2 pass 4/6 versus 3/6 across 3 seeds. That's not solved: one seed still answers with its own name.
- **Unclear speech:** still weak (K1 fails in most runs for both pipelines). It sometimes **claims to have performed actions**. No claim is made that hallucinations are solved.

## 4. Acceptance: same device, hand-graded, same 33 cases

| | Baseline (366ae73) | Candidate |
|---|---|---|
| Quality, seed 42 | 25/33 | 24/33 |
| Quality, seed 1 | 24/33 | 22/33 |
| Quality, seed 2 | 25/33 | 28/33 |
| **Quality, 3 seeds** | **74/99** | **74/99** |
| **Median TTFT, single-turn model answers** | **8.3 s** | **0.93 s** |
| p90 TTFT | 9.0 s | 1.1 s |
| Worst single-turn TTFT | 10.3 s | 2.2 s steady; 7–8 s for the first reply of the day (model load + snapshot build); 4.8–5.3 s for the reply right after a Stop |
| Long history (J1 / J2) | 50 s / 113 s | 24 s / 29 s |
| Prefill | 27.5 tok/s | ~60 tok/s; only the conversation part is evaluated |
| Decode (median) | 7.5 tok/s | 7.2 tok/s |
| Resident memory during generation | 2.99–3.05 GB | 2.82–2.92 GB, plus a 22.7 MB cache file |
| Arithmetic (D1 + J3, 3 seeds) | 3/6 | 6/6 |
| Multi-turn recall (G1 + G2, 3 seeds) | 3/6 | 4/6 |
| Stop → next request | Works (busy retry) | Works: the next request runs without the snapshot, the one after uses it again. No errors in 2 Stop cycles |

The per-seed spread (22–28) is larger than any difference between the pipelines. The single-seed figure (24 vs 25) is within that noise; the 3-seed totals are equal.

### Release-build smoke test (instrumented release APK, typed questions in the real UI, one conversation)

| Turn | Prompt tokens / evaluated | TTFT | Snapshot |
|---|---|---|---|
| 1st (includes one-time model load 5.5 s and snapshot build 4.9 s) | 220 / 19 | 5.7 s after load | restored in 26 ms |
| 2nd | 338 / 137 | 3.7 s | 42 ms |
| 3rd (after two long replies) | 576 / 375 | **9.9 s** | 36 ms |

Resident memory: 2.77–2.81 GB.

**Time to first token still grows with conversation length.** Only the system prompt is cached; the history is re-processed on every turn. The 3rd turn ran at about 38 tok/s (probe: 60 tok/s), probably thermal after hours of testing.

**Next step (P1):** also snapshot the state after each completed turn and restore it when the next prompt extends it exactly. This needs the template to re-render earlier replies token-identically; it has not been tried.

## 5. Remaining risks
- Thread counts and the snapshot were validated **only on the Tab S9 FE**. Re-run `perf_probe_test.dart` on the S10 before relying on 4 prefill threads there.
- The snapshot depends on llamadart 0.8.24's prefix-reuse behaviour and the ChatML template. Both are pinned. A llamadart upgrade must re-run the identical-output check (perf probe E2).
- Model limitations remain: knowledge cutoff (C3), unstable reasoning on word problems (D2/D3), clarification on corrupted speech (K1/K3), and occasional invented details.
