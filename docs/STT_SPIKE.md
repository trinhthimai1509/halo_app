# Vietnamese offline STT spike (sherpa-onnx)

Status: **spike completed and integrated.** Production code is in `lib/features/speech/`; see [SPEECH.md](SPEECH.md). The `spike/` app is kept only to reproduce these measurements.

## 1. Candidate and due diligence

| | |
|---|---|
| Engine | [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx), Flutter package `sherpa_onnx` **1.13.8**, pinned (Apache-2.0; publisher on pub.dev: unverified uploader, maintained by k2-fsa / Xiaomi) |
| ONNX Runtime | bundled by the package: `libonnxruntime.so` 22.2 MB plus `libsherpa-onnx-c-api.so` 4.5 MB (arm64-v8a) |
| Model | `sherpa-onnx-zipformer-vi-int8-2025-04-20`, an offline (non-streaming) Zipformer transducer, int8 |
| Model source | GitHub release `k2-fsa/sherpa-onnx` → `asr-models`, converted from [`zzasdf/viet_iter3_pseudo_label`](https://huggingface.co/zzasdf/viet_iter3_pseudo_label), about 70k hours of Vietnamese |
| Model licence | **Apache-2.0** (Hugging Face metadata tag of the upstream repo; its model card is otherwise empty) |
| Size | archive 60.2 MB (`.tar.bz2`). On disk 77.5 MB: encoder 70.9 MB, decoder 5.2 MB, joiner 1.0 MB, tokens and BPE 0.3 MB |
| SHA-256 (archive) | `48d0fdc9b3515eb9b00c4dfec2883207ee5ebe5c95b1959e7afce87fc3391938` |
| Audio capture | `record` 7.1.1 (BSD-3-Clause): PCM16, 16 kHz, mono, streamed to memory. Its Android plugin manifest merges `RECORD_AUDIO` |
| Platforms | Android: arm64-v8a, armeabi-v7a, x86, x86_64 `.so` files. iOS: `SherpaOnnxC.xcframework` (ios-arm64 plus simulator), podspec minimum iOS 13.0 |

**Rejected candidate:** `sherpa-onnx-zipformer-vi-30M-int8-2026-02-09`. It is smaller (about 32 MB) and reports a better WER, but its upstream ([`hynt/Zipformer-30M-RNNT-6000h`](https://huggingface.co/hynt/Zipformer-30M-RNNT-6000h)) is licensed **CC-BY-NC-ND-4.0**: non-commercial, no derivatives. That is unusable for this product.

**Output format:** the model emits **UPPER-CASE Vietnamese without punctuation**, for example `ÂM LƯỢNG TIVI GIẢM`. Diacritics are full NFC. The product needs at least sentence-casing before the text reaches the composer.

## 2. Spike code (not part of the app)

| File | Purpose |
|---|---|
| `spike/stt_vi/main.dart` | Standalone spike app (`flutter run -t spike/stt_vi/main.dart`): microphone recording, transcription, WER/CER, RSS, optional LLM load |
| `spike/stt_vi/stt_worker.dart` | `OfflineRecognizer` in a dedicated isolate. `decode()` is a blocking FFI call, so it stays off the UI isolate |
| `spike/stt_vi/text_metrics.dart` | Normalisation (lower-case, no punctuation, diacritics **kept**) plus WER and CER |
| `spike/stt_vi/utterances.dart` | The 7 fixed Vietnamese test sentences |
| `test/spike/text_metrics_test.dart` | Unit tests for the metrics |
| `test/spike/stt_host_test.dart` | Host (Windows) check of the model on its reference WAVs. Skipped unless paths are given |

**Audio handling:** PCM is collected in a `BytesBuilder` in memory. It is converted to float and sent to the worker, then dropped. Nothing is written to disk.

## 3. Method

- **Device:** see §4.
- **Build:** release, arm64, `--dart-define=LLM_METRICS=true`.
- **Model location:** pushed with adb to `/sdcard/Android/data/dev.offlineai.offline_ai_chat/files/stt/<model>/`.
- **Speaker:** a native Vietnamese speaker reads each sentence once, at normal pace, in a quiet room, about 30 cm from the device.
- **Network:** airplane mode during recognition. adb reconnects afterwards, and the logcat buffer is collected then.
- **Metrics** (one `[STT]` logcat line per event):
  - `audio_ms`;
  - `decode_ms`: decode time inside the worker;
  - `stop_to_text_ms`: from tapping Stop to having text, which is what the user waits for;
  - RTF;
  - WER and CER against the expected sentence, after normalisation;
  - process RSS (`VmRSS`);
  - `peak` sample amplitude, which proves real microphone signal.

## 4. Results (2026-10-08, Galaxy Tab S9 FE)

**Device:** Samsung Galaxy Tab S9 FE (SM-X510), Android 16 (API 36).
- SoC: Exynos 1380, 4× Cortex-A78 at 2.4 GHz plus 4× Cortex-A55 at 2.0 GHz.
- RAM: 7.5 GiB, about 3.0 GiB available at idle.
- Power: battery, about 40 %.

The **Galaxy S10 was not available.** The tablet was used by decision on 2026-10-08, so S10 results are NOT TESTED.

Raw log: [`stt_spike/spike_log_tab_s9_fe.log`](stt_spike/spike_log_tab_s9_fe.log). Release build, 2 STT threads.

### Accuracy: live microphone, native speaker

| # | Expected | Recognised | Audio | Peak | Decode | Stop→text | WER |
|---|---|---|---|---|---|---|---|
| 1 | Xin chào | XIN CHÀO | 3.28 s | 0.29 | 145 ms | 247 ms | 0 % |
| 2 | Hôm nay trời đẹp quá | HÔM NAY TRỜI ĐẸP QUÁ | 4.32 s | 0.21 | 178 ms | 293 ms | 0 % |
| 3 | Bạn có thể giúp tôi viết một email xin nghỉ phép không | *(identical)* | 4.48 s | 0.27 | 183 ms | 248 ms | 0 % |
| 4 | Giải thích cho tôi trí tuệ nhân tạo là gì bằng ngôn ngữ đơn giản | *(identical)* | 5.04 s | 0.17 | 216 ms | 307 ms | 0 % |
| 5 | Hẹn gặp bạn lúc ba giờ chiều thứ năm tuần sau ở quán cà phê gần nhà | *(identical)* | 6.72 s | 0.14 | 268 ms | 367 ms | 0 % |
| 6 | Tôi muốn nấu một bữa sáng nhanh và lành mạnh cho gia đình bốn người, bạn gợi ý giúp tôi vài món được không | …GIÚP TÔI **MỘT** VÀI MÓN… | 9.84 s | 0.11 | 411 ms | 542 ms | 4.2 % (one inserted word) |
| 7 | Cuối tuần này tôi định đưa các con đi dã ngoại ở ngoại thành Hà Nội, hãy lập giúp tôi danh sách những đồ cần mang theo và những lưu ý về thời tiết | *(identical)* | 10.48 s | 0.09 | 413 ms | 535 ms | 0 % |

**Overall: 1 error in 109 reference words, a WER of 0.92 %. Every diacritic was correct.**
- The #6 insertion ("một vài" for "vài") may be what the speaker actually said; there's no recording to check, by design.
- All of #1–#7 ran **with the LLM loaded** in the same process.
- Accepted runs are the final attempt of each sentence. Two earlier attempts of #1 are excluded from WER and covered in §5:
  - 20:28: 24.9 s of audio for a 1 s phrase; recognised "Ừ".
  - 21:14:02: clipped input (peak 1.000) during a cold start; recognised correctly.
- **Reference WAVs** (control, no microphone): the device output was identical to the Windows host output. RTF was 0.040–0.046.

### Latency

| | Value |
|---|---|
| Model load (first use) | **2.4 s** |
| Warm decode | 145–413 ms for 3.3–10.5 s of audio. RTF 0.039–0.044, about 40 ms per second of speech |
| Stop → text (what the user waits for) | **247–542 ms** |
| Cold decode after about 45 min idle, LLM loaded | **2393 ms** for 5.0 s of audio (RTF 0.475), about 11× slower than warm. The next utterance, 20 s later, was warm again (145 ms) |
| Idle, LLM *not* loaded (20:28, after about 27 min) | RTF 0.045, so no slowdown |

The cold-start penalty occurred only under memory pressure. With the LLM loaded, the device had moved 1.58 GB of the app's memory to swap (`TOTAL SWAP PSS`) by the time of collection. The likeliest cause is that the STT encoder's pages were swapped out and had to be read back on the first decode. That's an inference, not traced.

### Memory (VmRSS, sampled at events)

| State | RSS |
|---|---|
| Spike app idle | 185 MiB |
| STT loaded | 361 MiB (**+176 MiB**) |
| STT plus LLM loaded (peak observed) | **3040 MiB** |
| During #1–#7, LLM idle | 340–414 MiB. The LLM's memory-mapped weights were reclaimed by the OS while it was idle |

Not measured: an LLM *generation* right after a voice turn. Its weights would need paging back in, so time to first token after idle is likely higher than the figures in LLM_BENCHMARK.md.

### Offline evidence
- The release APK's merged manifest has only `RECORD_AUDIO`, with **no `INTERNET` permission**.
- The app's user ID (10407) has `gids=[]`, meaning no network group.
- The kernel's per-app traffic map (`dumpsys netstats`) has **no rows for 10407**.
- Recognition is an FFI call into `libsherpa-onnx-c-api.so` with local file paths only.
- **Airplane-mode test: NOT performed.** `airplane_mode_on` stayed 0 (setting generation 1, so unchanged since boot), Wi-Fi was on, and Wi-Fi ADB connected at 21:14:30.

### Audio retention
- PCM is collected only in memory (`BytesBuilder`), then dropped.
- The app's external storage holds no audio except the three reference WAVs pushed by adb.
- Internal storage couldn't be listed (release build), but the code never writes there.

## 5. Findings and limitations
1. **Clipping:** one take reached peak 1.000. With the `voiceRecognition` source and no auto-gain, a close or loud speaker clips. That take was still recognised correctly. Peaks of 0.09–0.29 are normal.
2. **No voice activity detection or length limit:** a 25 s take that was mostly silence produced "Ừ". Production needs a maximum duration, silence trimming, and an "I didn't catch that" path.
3. **Output is upper-case with no punctuation.** It needs sentence-casing. Proper nouns such as "Hà Nội" lose their capitals.
4. **Android 16 permissions:** folders created with `adb shell mkdir` under `Android/data/<pkg>/files` are owned by `shell` with mode 2770, so the app can't read them. They needed `chmod a+rwX`. This affects LOCAL_AI.md §3 on Android 11+ (it worked on the S10's Android 12) and is development setup only.
5. **APK size:** release arm64 went from 40 MB to **110 MB**. sherpa-onnx's prebuilt x86_64 and armeabi-v7a libraries (about 51 MB) bypass the ABI filter.
6. **Windows host only:** System32 contains an older `onnxruntime.dll` (1.17), so host tests must preload the package's copy.
7. **Distribution conditions:**
   - Apache-2.0 for sherpa-onnx and the model (ship the licence text plus attribution).
   - MIT for ONNX Runtime.
   - BSD-3 for `record`.
   - The model's upstream card is empty, so training-data provenance is undocumented. Recommend legal sign-off.
   - **Do not ship `test_wavs/`**: they come from `nguyenvulebinh/wav2vec2-base-vietnamese-250h`, a CC-BY-NC source.
