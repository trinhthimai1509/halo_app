# LLM answer quality: Vietnamese evaluation and fixes (2026-10-08)

> **Update 2026-10-09:**
> - The response-time work ([LLM_PERFORMANCE.md](LLM_PERFORMANCE.md)) took the median time to first token from 8.3 s to 0.93 s.
> - It also added Dart arithmetic answers and a "tôi = the user" prompt line, and removed the clock time from the prompt.
> - Quality re-measured over 3 seeds, hand-graded: **74/99 before and after**. The latency table in §3 below describes the 366ae73 state.
> - Later the same day: Gregorian calendar facts in Dart, a correction-handling rule and Markdown rendering (§7).

**Device:** Galaxy Tab S9 FE (SM-X510, Exynos 1380, Android 16).
**Model:** Qwen3.5-2B Q4_K_M with llama.cpp (llamadart 0.8.24), 2 threads, `n_ctx` 4096.
**Not changed:** the model and the STT engine.

**Evidence:** [test_evidence/llm_quality_2026-10-08/](test_evidence/llm_quality_2026-10-08/). It holds every prompt and output as JSON, plus the `[LLM]` metric lines.
**Suite:** [`integration_test/quality_eval_test.dart`](../integration_test/quality_eval_test.dart).

## 1. Reported failures and root causes

| Symptom (from the tablet) | Root cause | Type |
|---|---|---|
| "Xin chào hôm nay là thứ mấy" → "Thứ tư", then "I don't know the date" | The system prompt was a fixed English sentence with **no date or time**. The model has no clock, so any weekday it gives is a guess | **Missing application context** (implementation defect) |
| A garbled transcript produced a long, unrelated answer about ransomware, FileVault and USB security | No instruction to ask for clarification or to distrust speech-recognition errors. The old sampling (temperature 1.0, top_p 1.0) let a 2B model run with any reading | Missing instruction plus sampling. **Remains partly a model limit** (§4) |
| Chinese words inside Vietnamese answers ("苹果") | presence_penalty 2.0. The model card itself warns that high values may cause language mixing | Inference parameter |
| Confident invented facts (an author, a gold-price brand, a day "387", the model's own release date) | No rule against guessing, plus the high-variance sampling above | Prompt plus sampling, and **model capability** |
| Markdown (`**`, `###`) shown as raw text | The model's default style; the UI renders plain text | Prompt (fixed by instruction, 18/33 → 2/33) |

### Verified correct (no defect)
- **Chat template:** the GGUF's own ChatML Jinja template. `<|im_start|>system … <|im_end|>`, then the user turn, then `assistant` with an **empty `<think></think>` block**, so thinking is disabled correctly. Dumped verbatim in `prompt_inspection_*.json`. No duplicate BOS or stray tokens.
- **History serialization:**
  - `ChatController` passes an immutable snapshot of earlier messages, and `SendMessage` appends the new user turn exactly once.
  - The roles are correct.
  - It is now covered by a 3-turn no-duplication unit test.
  - `prompt_msgs` in the device logs matches the expected counts (e.g. 16 and 36 messages for the long-history cases).
- **Context policy:** oldest turns are dropped first and the system prompt is always kept (J2, with 2 messages trimmed, behaved as designed).
- **Stopping:** natural EOS, capped at `maxNewTokens` 1024. Stop and streaming are unchanged.

## 2. Changes

| File | Change |
|---|---|
| `lib/features/chat/domain/local_time_context.dart` (new) | Vietnamese and English weekday/date strings, time, and UTC offset from a `DateTime`; DST-safe day shifting |
| `lib/features/chat/domain/calendar_answers.dart` (new) | **Plain calendar questions are answered in Dart from the device clock**, never by the model. Covered: today, tomorrow, yesterday, weekday or date, the current time, and an English variant. Matching is strict: after removing a greeting or politeness prefix and trailing particles, the whole message must be the question. Anything else goes to the model |
| `lib/features/chat/domain/assistant_instructions.dart` | `systemPrompt(DateTime now)`: a Vietnamese prompt **built per request** with the current date, time and offset, plus rules: answer in the user's language, concisely, on topic; do normal tasks normally; use what the user said earlier; don't invent, and say you don't know for live data or uncertain facts; ask for clarification on unclear (possibly mis-transcribed) input; no Markdown |
| `lib/features/chat/domain/usecases/send_message.dart` | Calendar shortcut first (persisted like any reply, with no model load); otherwise the dated system prompt from the injected clock |
| `lib/features/local_ai/data/llama_cpp/llm_model_config.dart` | Sampling moved from the card's "non-thinking text" set (temp 1.0, top_p 1.0, presence 2.0) to its other official non-thinking set: **temp 0.7, top_p 0.8, top_k 20, presence 1.5** |
| `integration_test/quality_eval_test.dart` (new) | A 33-case on-device suite: exact-prompt dump, the exact pre-fix pipeline, and the production pipeline |
| Tests | `calendar_answers_test` (17), `assistant_instructions_test` (3), `send_message_test` (+2: no history duplication, calendar shortcut without a model call) |

No date is hard-coded anywhere. Every value comes from `DateTime.now()`, injected as the app clock, at request time.

## 3. Results: real model, real device, same 33 cases

**Grading:**
- Every output was **graded by hand**; the automatic keyword checks in the harness were too lenient.
- One example: "xác minh" matched the expected name "Minh".
- The verdicts and reasons are in the table below.

**Runs:**
- **Before:** the exact pre-fix pipeline (legacy prompt and sampling).
- **v1:** the first fixed prompt.
- **v2:** the shipped prompt, which reworded v1's over-broad "say you don't know" rule.

All runs used a fixed seed of 42. The "before" run capped replies at 192–256 tokens; the production runs use the app's normal limit of 1024.

| Category | Before | v1 | v2 (shipped) |
|---|---|---|---|
| A. Date & weekday | 0/3 | 3/3 | 3/3 |
| B. Basic conversation | 2/3 | 3/3 | 3/3 |
| C. General knowledge | 2/3 | 2/3 | 2/3 |
| D. Arithmetic & reasoning | 1/3 | 1/3 | 1/3 |
| E. Instruction following | 1/3 | 1/3 | 3/3 |
| F. Writing | 1/3 | 2/3 | 2/3 |
| G. Multi-turn context | 2/3 | 2/3 | 1/3 |
| H. Hallucination avoidance | 0/3 | 3/3 | 3/3 |
| I. Voice transcript → LLM | 0/3 | 3/3 | 3/3 |
| J. Long history | 3/3 | 0/3 | 3/3 |
| K. Ambiguous / corrupted input | 1/3 | 2/3 | 1/3 |
| **Total** | **13/33** | **22/33** | **25/33** |

### Per case

| ID | Input | Before | v1 | v2 (shipped) | Before → v2 notes | TTFT before / v2 | v2 prompt tok | v2 tok/s |
|---|---|---|---|---|---|---|---|---|
| A1 | Hôm nay là thứ mấy? | **FAIL** | PASS | PASS | declined, invented reason → Dart: Thứ Năm 8/10/2026 | 1.3s / 18 ms | — | — |
| A2 | Hôm nay là ngày bao nhiêu, tháng mấy, năm nào? | **FAIL** | PASS | PASS | invented "2025, day 387", Russian word → Dart: correct | 1.4s / 1 ms | — | — |
| A3 | Ngày mai là thứ mấy? | **FAIL** | PASS | PASS | declined → Dart: Thứ Sáu 9/10/2026 | 1.2s / 4 ms | — | — |
| B1 | Xin chào, bạn là ai? | **FAIL** | PASS | PASS | claims to be "Qwen3.5 released Oct 2026, understands Chinese" → introduces itself as Halo | 1.3s / 8.9s | 217 | 8.88 |
| B2 | Cảm ơn bạn nhiều nhé! | PASS | PASS | PASS |  | 1.5s / 6.2s | 216 | 8.20 |
| B3 | Bạn có nói được tiếng Việt không? | PASS | PASS | PASS |  | 1.4s / 7.0s | 217 | 7.60 |
| C1 | Thủ đô của Việt Nam là thành phố nào? | PASS | PASS | PASS |  | 1.5s / 7.1s | 220 | 7.99 |
| C2 | Nước sôi ở bao nhiêu độ C ở áp suất khí quyển tiêu chuẩn? | PASS | PASS | PASS |  | 1.5s / 7.3s | 225 | 8.09 |
| C3 | Việt Nam có bao nhiêu tỉnh thành sau khi sáp nhập năm 2025? | **FAIL** | **FAIL** | **FAIL** | invented legislative story → invents "174 provinces" (v1: "Không biết") | 1.8s / 7.4s | 227 | 8.46 |
| D1 | 17 cộng 25 bằng bao nhiêu? | **FAIL** | PASS | **FAIL** | multiplied instead of adding → "32" (v1: 42) - unstable | 1.5s / 7.7s | 219 | 3.31 |
| D2 | Một quyển vở giá 12.000 đồng. Mua 3 quyển thì hết bao nhi… | PASS | **FAIL** | **FAIL** |  → "72.000" (v1: "Không biết") | 2.1s / 7.9s | 232 | 7.80 |
| D3 | An có 5 quả táo, cho Bình 2 quả rồi mua thêm 4 quả. Hỏi A… | **FAIL** | **FAIL** | PASS | Chinese "苹果" inside Vietnamese → correct, step by step | 2.3s / 7.9s | 236 | 7.82 |
| E1 | Liệt kê đúng 3 loại trái cây, mỗi loại một dòng, không gi… | **FAIL** | **FAIL** | PASS | English/misspelled "Apple, Banan" → 3 Vietnamese fruits | 2.1s / 8.2s | 230 | 6.95 |
| E2 | Chỉ trả lời "có" hoặc "không": Hà Nội có phải là thủ đô c… | PASS | **FAIL** | PASS |  → "có" (v1: "không" - wrong) | 2.2s / 8.3s | 231 | null |
| E3 | Hãy trả lời bằng tiếng Anh: "Xin chào" nghĩa là gì? | **FAIL** | PASS | PASS | answered "Bình yên" → "Hello means Xin chào" | 1.9s / 8.0s | 225 | 7.19 |
| F1 | Viết một câu chúc mừng sinh nhật ngắn gọn dành cho mẹ. | PASS | PASS | PASS |  | 1.8s / 7.7s | 223 | 7.50 |
| F2 | Viết một email ngắn gửi quản lý để xin nghỉ phép một ngày… | **FAIL** | **FAIL** | **FAIL** | usable but "Dear", typos → email written; header shows wrong weekday "Chủ nhật" next to the injected date (v1: refused) | 1.9s / 8.1s | 227 | 7.82 |
| F3 | Tóm tắt trong một câu: "Hôm nay trời mưa to nên tôi ở nhà… | **FAIL** | PASS | PASS | summary invented facts → one correct sentence | 2.6s / 9.0s | 238 | 7.71 |
| G1 | Tên tôi là gì? | **FAIL** | **FAIL** | **FAIL** | rambles, never says "Minh" → talks about itself, never says "Minh" | 2.8s / 8.5s | 241 | 7.86 |
| G2 | Vậy tôi nuôi tổng cộng bao nhiêu con vật? | PASS | PASS | **FAIL** | 3 (garbled words) → "5 con vật (2 + 1)" - wrong | 3.2s / 9.9s | 258 | 6.99 |
| G3 | Bạn đang gọi tôi là gì? | PASS | PASS | PASS |  | 4.2s / 10.3s | 281 | 6.00 |
| H1 | Giá vàng SJC hôm nay là bao nhiêu một lượng? | **FAIL** | PASS | PASS | declines but invents "Vàng Nhật Bản Cống" → declines cleanly | 1.9s / 8.2s | 221 | 7.03 |
| H2 | Tối qua trận bóng đá Việt Nam gặp Thái Lan kết thúc với t… | **FAIL** | PASS | PASS | speculates → declines | 2.3s / 8.6s | 228 | 7.84 |
| H3 | Ai là tác giả cuốn tiểu thuyết "Những ngọn đèn trên đồi M… | **FAIL** | PASS | PASS | invents an author "Tống Quang" → says it does not know | 2.6s / 8.5s | 235 | 7.71 |
| I1 | Xin chào hôm nay là thứ mấy | **FAIL** | PASS | PASS | "Hôm nay là Thứ ba" (wrong day) → Dart: correct, with greeting | 1.8s / 2 ms | — | — |
| I2 | Giải thích cho tôi trí tuệ nhân tạo là gì bằng ngôn ngữ đ… | **FAIL** | PASS | PASS | incoherent ("giới tính", "2035") → clear explanation | 2.2s / 8.4s | 224 | 7.91 |
| I3 | Tôi muốn nấu một bữa sáng nhanh và lành mạnh cho gia đình… | **FAIL** | PASS | PASS | garbled ("mì chính", "Vải trứng") → reasonable suggestions (Markdown list) | 2.5s / 9.2s | 234 | 7.31 |
| J1 | Mã đơn hàng của tôi là gì? | PASS | **FAIL** | PASS | HX-4821 → HX-4821 (v1: claimed no info - FAIL) | 42.9s / 50.3s | 1254 | 6.89 |
| J2 | Mã đơn hàng của tôi là gì? | PASS | **FAIL** | PASS | HX-4821 (fact still in window) → fact trimmed by policy; says no info, but offers an Internet search it cannot do | 108.1s / 112.9s | 2855 | 7.23 |
| J3 | 17 cộng 25 bằng bao nhiêu? | PASS | **FAIL** | PASS | 42 → 42 (v1: "32") | 77.3s / 87.6s | 2193 | 3.98 |
| K1 | Sau khi hoàn thành tắt e mốt và gửi đăng cho clo để nó đọ… | **FAIL** | **FAIL** | **FAIL** | invents an "e-mode / Clo" procedure → no ransomware story, but assumes an app and lists steps instead of asking | 1.7s / 8.8s | 231 | 7.45 |
| K2 | Ừ cái đó thì sao | PASS | PASS | PASS | asks what "cái đó" is → asks what the user means | 1.2s / 9.0s | 214 | 7.17 |
| K3 | Bật cái lớp cho tôi với | **FAIL** | PASS | **FAIL** | asks, but invents a date "14/05/2029" → assumes "online class" (v1 asked correctly) | 1.4s / 8.6s | 216 | 7.23 |

Calendar answers (A1–A3, I1) take 1–18 ms and make no model call.

### Latency, speed and memory

| | Before | After (v2) |
|---|---|---|
| System prompt | 38 tokens | 214–238 tokens with the date and rules |
| **Time to first token, single-turn model answers (median)** | **1.4 s** | **8.3 s** |
| Calendar questions | 1.2–1.8 s (wrong answers) | **≤ 18 ms** (correct) |
| Long history (1.1k / 2.1k / 2.8k prompt tokens) | 43 / 77 / 108 s | 50 / 88 / 113 s |
| Decode speed | 7–9 tok/s | 6–9 tok/s (unchanged) |
| Average reply length | 303 characters (capped run) | 168 characters |
| Markdown in replies | 18 of 33 | 2 of 33 |
| Resident memory with the model loaded | ≈ 3.0 GB | ≈ 3.0 GB (a longer prompt is negligible) |

**The rules cost about 7 s of time to first token on every model turn.**
- Prompt processing on this tablet runs at only about 25–27 tokens/s.
- There is no KV-cache reuse with this model (LLM_BENCHMARK.md), so the system prompt is re-processed on every request.
- This is the main cost of the fix, and the main performance risk (§5).

## 4. Remaining failures (v2) and their type

| Case | What happens | Type |
|---|---|---|
| D1, D2, G2 | Simple arithmetic is **unstable**: "17 + 25 = 32", "12.000 × 3 = 72.000", "2 + 1 = 5". Each case flips between runs (D1 and J3 swap between v1 and v2) | **Model limitation** at 2B / Q4 |
| C3 | Invents "174 provinces". v1 said "I don't know"; it lacks knowledge of the 2025 merger | Model knowledge plus hallucination |
| G1 | Doesn't use the name from the previous turn, in every run | Model limitation (multi-turn) |
| F2 | The email header puts a **wrong weekday ("Chủ nhật") next to the injected date** | Model copies context unreliably. Mitigation: P1-2 |
| K1, K3 | Corrupted speech: no more invented ransomware topic, but it still assumes an app or class instead of asking | Mostly model limitation; prompt helps only partly |
| J2 | Correctly says it has no order code (the fact was trimmed), then offers an Internet search it cannot do | Minor hallucinated capability |

**Separation:**
- **Implementation bugs fixed:** the missing date/time context, the guessable calendar questions, and the high-variance sampling.
- **Missing app context:** the date/time is now provided.
- **Model limitations:** arithmetic, multi-turn recall, knowledge after the training cutoff, and clarification behaviour.

## 5. Recommendations

| Priority | Recommendation | Expected impact |
|---|---|---|
| P0 | **Ship the fix (done)**: date/time context, Dart calendar answers, the anti-guessing prompt, the new sampling | Quality 13/33 → 25/33; date questions always correct; no invented live data |
| P1-1 | **Recover time to first token:** try 4 threads for *prompt* processing only (`numberOfThreadsBatch`). Prefill is compute-bound, while the S10 stall problem was in decode. Also trim the prompt to the rules that measurably helped | Potentially halves the 6–7 s prefill cost; must be re-measured |
| P1-2 | Do simple arithmetic in Dart, like the calendar answers (a plain "a + b" / "a × b" expression) | Removes the most visible "dumb" errors |
| P1-3 | Lower the context budget (currently 3008 tokens) so the worst-case time to first token stays under about 30 s | Long chats stop waiting about 2 minutes |
| P1-4 | Render or strip residual Markdown in the UI | Cosmetic |
| P1-5 | Evaluate a stronger model (below) with this same suite before deciding | Capability gaps in §4 |

### Is Qwen3.5-2B Q4_K_M enough for the MVP?
- **Enough for a demo-quality MVP:** greetings, explanations, short writing, declining unknowns, and voice-question replies.
- **Not reliable** for arithmetic, multi-turn recall, or clarifying corrupted speech.
- At 25/33, the remaining failures are mostly **model limits**, not implementation defects. **Keep it for the 11 Oct delivery** (no time to re-validate a new model), and document the limits.

**Two realistic alternatives for 6–8 GB Android devices.** Neither has been downloaded or tested; sizes and speeds are estimates.
1. **Qwen3.5-4B Q4_K_M** (Apache-2.0, same family, template and runtime):
   - about 2.5–2.8 GB file;
   - roughly 2× slower: decode about 4 tok/s on this tablet, and prefill also about half as fast;
   - the most likely large quality gain;
   - memory is tight on 6 GB phones.
2. **Qwen3.5-2B at Q8_0** (about 2 GB):
   - same speed class, slightly slower decode;
   - removes 4-bit quantization error, which can matter for Vietnamese diacritics and arithmetic;
   - a cheaper experiment than changing model size.

## 6. Reproducing
```bash
flutter test integration_test/quality_eval_test.dart -d <serial> --no-uninstall --dart-define=QE_BEFORE=all
```

The device must stay **unlocked with the screen on**. A dozing screen lets the OS freeze the app, and the test tool then aborts the run. The suite takes about 15 minutes per pipeline. Results are written to `<external files>/qe/*.json`.

## 7. Calendar hallucinations and correction handling (2026-10-09)

**Reported** (tablet, 2026-10-09 20:13, release build). Asked "Tháng này có bao nhiêu ngày", the model said 31 but also:
- that it had no Internet to look the month up;
- that October 2026 is a "tháng nhuận" (the Gregorian calendar has no leap months);
- it kept defending this when corrected and invented leap months "4, 7, 9 hoặc 11";
- it showed raw `**31 ngày**`.

**Changes**

| File | Change |
|---|---|
| `lib/features/chat/domain/gregorian_answers.dart` (new) | Month length, year length, leap year and "is month X a leap month" are **computed in Dart**: this/next/last month, month words, "năm nay/sau/ngoái/2028". The question must end the message ("Biết là tháng mười mà … có bao nhiêu ngày à" matches). Corrections such as "Tôi không nói lịch âm" and anything else go to the model |
| `send_message.dart` | Chain: clock answers → Gregorian answers → arithmetic → model. Dart replies are persisted like model replies, so **follow-up turns see them in the history** (unit test replays the reported conversation and checks the exact request) |
| `assistant_instructions.dart` | One rule: when told it is wrong, admit and correct briefly if the user is right; don't invent explanations; never claim to need Internet, a device or another app |
| `presentation/widgets/markdown_lite.dart` (new) | Assistant text renders `**bold**`, `*italic*`, `` `code` ``, `#` headings, bullets and `---` rules instead of showing markers. Unclosed markers (mid-stream), `2 * 3` and `snake__case` stay literal. No links or HTML are interpreted |

**Context-loss audit (no defect found):**
- History is the controller's full persisted message list, including Dart answers; `SendMessage` appends the user turn once.
- Messages are stored in SQLite with role and content, so a reopened conversation sends the same history.
- `ContextWindowPolicy` drops oldest turns only when the prompt exceeds 1536 tokens. The reported 5-turn conversation is about 600 tokens.
- The prompt snapshot contains only the system block, is keyed by its exact text, and is used only when the rendered prompt starts with it. It cannot carry state from another conversation. Changing the prompt (as here) rebuilds it once (about 3–4 s).

**Real-model results** (Tab S9 FE, seeds 42/1/2, the exact conversation plus "Bạn chắc không?" and "Sao lúc nãy nói khác?"; evidence in [test_evidence/calendar_fix_2026-10-09/](test_evidence/calendar_fix_2026-10-09/); hand-graded):

| | ff857ff | This change |
|---|---|---|
| Turns 1–3 (date, month length ×2) | 6/9 correct; "30 ngày" once, "không biết" twice (once "không kết nối internet để tra cứu") | **9/9** correct, from Dart (0 ms model time) |
| Turns 4–7 (corrections and challenges), acceptable replies | 3/12 | **8/12** |
| Replies claiming no Internet / needing to look things up | 4/18 | **0/12** |
| Replies calling October a leap month or inventing leap months | 3/18 (plus "30 ngày" twice) | **0/12** |
| Remaining faults | | An invented month-length list (seed 42), hedging on "Bạn chắc không?" (seeds 1, 2), Markdown in 4 replies (now rendered) |

A stronger wording ("…nếu câu trả lời trước đã đúng, hãy khẳng định lại") was tried and **rejected**. It scored 5/12, invented leap-year reasoning, and once parroted the rule back to the user (`calendar_conversation_rejected_prompt.json`).

**No regression on the 33-case suite** (same seeds, both pipelines in one run):

| | ff857ff | This change |
|---|---|---|
| Auto-graded | 83/99 (27/26/30) | 86/99 (28/28/30) |
| Hand review of the 7 cases whose result differs | 11/21 | 11/21 |
| Single-turn TTFT median / p90 | 0.79 s / 0.99 s | 0.78 s / 0.96 s |
| Long-history J1 / J2 TTFT | 23.1–23.3 s / 26.8–28.2 s | 23.6–24.1 s / 27.0–27.4 s |
| Decode | 7.8 tok/s | 7.7 tok/s |

The system prompt grew from 201 to 246 tokens. Because it is snapshotted, this costs nothing per request. In the calendar conversation the first model turn includes the one-time snapshot build (about 4 s). In the ff857ff run the same cost lands on turn 2, which is now answered instantly.

**Limits:** follow-up corrections are still answered by a 2B model. The rule reduced, but did not remove, hedging and invented explanations.
