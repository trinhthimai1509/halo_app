# Speech-to-text (offline, Vietnamese)

Status (2026-10-08): **integrated on Android** and verified on a Galaxy Tab S9 FE. Not available on iOS: the app shows a clear "not available" message there and never returns invented text.

The engine was selected in the spike documented in [STT_SPIKE.md](STT_SPIKE.md).

## 1. Engine and model

| | |
|---|---|
| Runtime | [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx), Flutter package `sherpa_onnx` **1.13.8** (pinned), with ONNX Runtime bundled |
| Model | `sherpa-onnx-zipformer-vi-int8-2025-04-20`: offline Zipformer transducer, int8, Vietnamese |
| Model licence | Apache-2.0. Upstream is [`zzasdf/viet_iter3_pseudo_label`](https://huggingface.co/zzasdf/viet_iter3_pseudo_label), trained on about 70k hours |
| Files installed | `encoder-epoch-12-avg-8.int8.onnx` (70.9 MB), `decoder-epoch-12-avg-8.onnx` (5.2 MB), `joiner-epoch-12-avg-8.int8.onnx` (1.0 MB), `tokens.txt`. About 77 MB in total |
| **Not installed** | `test_wavs/` from the release archive. They come from a **CC-BY-NC** source and must never ship |
| Audio capture | `record` 7.1.1 (BSD-3-Clause): 16 kHz mono PCM16, `voiceRecognition` input, streamed to memory |

## 2. Architecture

```
ComposerController (presentation)          30 s limit, error mapping, no voice while the LLM generates
   │
SpeechToTextService (speech/domain)        start → stop/cancel → transcript
   ▲
SherpaSpeechToTextService (speech/data)
   ├─ AudioCapture / RecordAudioCapture     microphone → PCM16 in RAM (no file)
   ├─ AudioSignal                           PCM → float, silence trimming, peak
   ├─ SpeechRecognizer / SherpaRecognizer   sherpa-onnx in its own isolate
   ├─ SttModel / SttModelLocator            model files and where they live
   └─ TranscriptFormatter (domain)          UPPER CASE → sentence case
```

- **Dependency injection** (`lib/app/di/providers.dart`):
  - Android gets `SherpaSpeechToTextService` and `LlamaCppLocalAiService`.
  - Other platforms get `UnsupportedSpeechToTextService` and `UnsupportedLocalAiService`, which fail with a clear message.
  - Fakes exist only under `test/fakes/` and are injected by tests. **No production code path can reach a fake.**

### Session lifecycle
1. **Tap 🎤** → `initialize()`:
   - asks for microphone permission (Android runtime dialog);
   - starts loading the model **in the background** (about 2.4–2.9 s, in an isolate).
2. **`startListening()`:**
   - recording starts immediately, so the UI is never blocked by model loading;
   - a warm-up decode of 0.5 s of silence runs while the user speaks, bringing back model pages the OS may have reclaimed.
3. **Tap ✓, or the 30 s limit fires** → `stopListening()`:
   - PCM is converted to float;
   - leading and trailing silence is trimmed (30 ms frames, RMS ≥ 0.008, 300 ms padding, at least 150 ms of speech);
   - the trimmed audio is decoded in the isolate and the result formatted;
   - the buffer is dropped.
4. **Tap ✕** → `cancelListening()`: the recorder stops and the buffer is cleared.
5. **The transcript is inserted into the composer**, not auto-sent, so the user can correct it before sending.

### Error handling (`VoiceError` → snackbar)

| Case | Detection | Message |
|---|---|---|
| Permission denied | `hasPermission()` false → `MicrophonePermissionException` | "Voice input needs microphone access. Allow it in Settings." |
| Silence or no speech | No frame above the threshold, or under 150 ms of speech → `''` | "Didn't catch that. Please try speaking again." |
| Model missing | `SttModelLocator.find` null → `ModelUnavailableException` | "The on-device speech model is not installed. See docs/SPEECH.md." |
| Recognizer failure, crash or 30 s timeout | `TranscriptionException`. The broken recognizer is disposed and reloaded on the next session | "Voice input is not available right now." |
| Cancel during the permission dialog | Session token; capture is never started or is cancelled immediately | none |

### Resource rules
- **One model load per process.** The recognizer is reused across sessions; a failed load is retried on the next session.
- **About 176 MiB resident** when loaded. It stays loaded and is freed in `dispose()` along with the provider.
- **No overlapping heavy inference.** The 🎤 is disabled while the LLM generates; while recording or transcribing, the composer shows the voice UI and nothing can be sent.

## 3. Model installation

> **Customers** import `halo-stt-vi.zip` in the app (AI models screen); see [MODEL_INSTALL.md](MODEL_INSTALL.md). The ADB steps below are for development. An imported model takes precedence.

### Development (validated)
```bash
# From the extracted release archive. Push the model files only, never test_wavs/.
adb shell mkdir -p /sdcard/Android/data/dev.offlineai.offline_ai_chat/files/stt/sherpa-onnx-zipformer-vi-int8-2025-04-20
adb push encoder-epoch-12-avg-8.int8.onnx decoder-epoch-12-avg-8.onnx joiner-epoch-12-avg-8.int8.onnx tokens.txt /sdcard/Android/data/dev.offlineai.offline_ai_chat/files/stt/sherpa-onnx-zipformer-vi-int8-2025-04-20/
# Android 11+ (verified on Android 16): folders created by `adb shell` are
# owned by `shell` (mode 2770) and unreadable by the app. Open them up:
adb shell chmod -R a+rwX /sdcard/Android/data/dev.offlineai.offline_ai_chat/files/stt /sdcard/Android/data/dev.offlineai.offline_ai_chat/files/models
```

The same `chmod` applies to the LLM folder `files/models/`, see [LOCAL_AI.md §3](LOCAL_AI.md). Git-Bash users need `MSYS_NO_PATHCONV=1`, otherwise `/sdcard/...` is rewritten into a Windows path.

`SttModelLocator` searches, in order:
1. `<external files>/stt/<model>/` (development);
2. `<application support>/stt/<model>/` (production target).

All four model files must be present.

### Production delivery (implemented 2026-10-09: in-app import, see MODEL_INSTALL.md)

ADB is a development mechanism only. A shipped build must place **both** models in app-private storage (`getApplicationSupportDirectory()`):

| Model | Size |
|---|---|
| LLM | 1.19 GiB |
| STT | 77 MB |

Requirements for any delivery mechanism:
- Fully offline after install: no cloud inference and no runtime download backend (out of scope).
- Integrity check (SHA-256, listed in LOCAL_AI.md §2 and STT_SPIKE.md §1) before first use.
- Never include `test_wavs/`.
- Survive app updates. They must not be deleted by `adb install -r`-style updates; `Android/data` is deleted on uninstall.

Candidate approaches (product decision):
- An in-app "import model files" step from local storage.
- Bundling the STT model (77 MB) as an APK/AAB asset that is copied on first run. The 1.19 GiB LLM is too large for a normal APK.
- Play Asset Delivery.

## 4. Verification (2026-10-08)

**Device:** Galaxy Tab S9 FE (SM-X510, Exynos 1380, Android 16). Release build with `LLM_METRICS=true`. Evidence: [test_evidence/2026-10-08_stt_integration_tab_s9_fe.log](test_evidence/2026-10-08_stt_integration_tab_s9_fe.log).

| Check | Result |
|---|---|
| Permission denied, then allowed | **PASS**. The system dialog was shown twice: the first was denied (no recording, no model load), the second allowed (model loaded at 21:57:29). The snackbar text itself was not captured |
| Real Vietnamese voice → composer | **PASS**. "Xin chào hôm nay là thứ mấy", correct and sentence-cased, 318 ms from Stop to text |
| Transcript sent → real local LLM | **PASS**. The LLM loaded (5.5 s) and replied with 61 tokens: time to first token 1.1 s, 7.9 tok/s |
| Second voice turn with English words | **Recognition limitation**, see §5. It reached the LLM, which replied (328 tokens, 7.6 tok/s) |
| Cancel | **PASS**. Two cancels, no decode, the composer stayed empty |
| 30 s maximum | **PASS**. Auto-stop at exactly `audio_ms=30000` without a tap; decoded in 1.5 s |
| 🎤 disabled during generation | **PASS** (accessibility tree: `Voice input enabled=false` while `Stop generating` was visible) |
| Stop during generation | **PASS**. `generation_cancelled`; app CPU 0.0% right after; 🎤 re-enabled |
| Repeated sessions and memory | **PARTIAL**. 6 voice sessions in one process (2 speech, 2 cancels, 2 long recordings). RSS before the LLM loaded: 391–430 MiB; with the LLM: 3001–3081 MiB; no growth trend. A longer soak (20+ sessions) was not run |
| Silence → "Didn't catch that" | **NOT TESTED on device**: the room had background speech, which was correctly transcribed instead. Covered by unit tests |
| Offline | **PARTIAL**. Wi-Fi was off for the whole session (Wi-Fi-only tablet). The release build has no `INTERNET` permission (`gids=[]`), and `netstats` has no traffic rows for the app's user ID. **Airplane mode was not enabled**, and a validated USB-tethering network (`usb0`) existed on the device |

**Latency on device** (release build):
- Stop → text: 318 ms (4.5 s of audio), 485 ms (10.2 s), 1267 ms (21.3 s), 1624 ms (30 s).
- Decode RTF ≈ 0.04–0.05.
- Model load: 2.9 s, hidden behind recording.

**Unit and widget tests:** `flutter test` gives 72 passed and 2 skipped (the host-only real-model tests). Those two also pass when run with `STT_MODEL_DIR`/`STT_LIB_DIR`.

## 5. Known limitations
1. **Code-switching (Vietnamese with English words).** The model is Vietnamese-only.
   - English words it didn't learn are spelled as Vietnamese syllables. For example, "test", "log" and "Claude" came out as "tắt", "lớp" and "clo" in a real session.
   - Common loanwords seen in training work ("email", "USB").
   - Mitigation today: the transcript is editable before sending.
   - Possible improvement: sherpa-onnx hotword biasing for a fixed product vocabulary. It needs `modified_beam_search` and a word list, and is untested.
   - A multilingual model would be a separate engine evaluation.
2. **No punctuation, and proper nouns are lower-cased.** The model emits upper case without punctuation, so "HÀ NỘI" becomes "hà nội". Nothing is invented.
3. **Background speech is transcribed.** There's no speaker separation; a TV or other people near the device end up in the transcript.
4. **No streaming or partial results.** The text appears after Stop (offline transducer).
5. **Android 16 adb folder permissions** (development only, §3).
6. **iOS:** not integrated. The sherpa-onnx iOS xcframework exists (iOS ≥ 13) but has never been built here (no Mac).
