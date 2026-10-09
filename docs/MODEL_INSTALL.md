# Installing Halo and its AI models (Android)

Halo works **fully offline**. It never downloads anything and has no Internet permission. The two AI models are delivered as files next to the app, and the customer imports them once from inside Halo.

## 1. What the customer receives

| File | Size | SHA-256 | Purpose |
|---|---|---|---|
| `halo-release.apk` | 65.0 MB | (per build) | The app (arm64 Android phones and tablets) |
| `Qwen3.5-2B-Q4_K_M.gguf` | 1,280,835,840 bytes (1.28 GB) | `aaf42c8b7c3cab2bf3d69c355048d4a0ee9973d48f16c731c0520ee914699223` | Local AI (chat) model |
| `halo-stt-vi.zip` | 58,251,328 bytes (58 MB) | `925fe1353894fdd521b9ddeece4a92acf518566b9d4bdb9faecbba4ada63597c` | Vietnamese speech model |

**Building `halo-stt-vi.zip`:** run `python -I tool/make_stt_package.py <extracted official model dir> halo-stt-vi.zip`.
- The input is the official sherpa-onnx release `sherpa-onnx-zipformer-vi-int8-2025-04-20`.
- The script verifies every file's hash and never includes the release's `test_wavs/`, which come from a non-commercial source.
- The ZIP is reproducible from the official files. Its own SHA-256 above is for this build.

**What gets installed:** inside the app's private storage, exactly these files, each checked by size and SHA-256:

| Installed file | Bytes | SHA-256 |
|---|---|---|
| `Qwen3.5-2B-Q4_K_M.gguf` | 1,280,835,840 | `aaf42c8b…699223` |
| `encoder-epoch-12-avg-8.int8.onnx` | 70,876,129 | `b3abdef7…522124` |
| `decoder-epoch-12-avg-8.onnx` | 5,165,084 | `d1d27cca…1d9998` |
| `joiner-epoch-12-avg-8.int8.onnx` | 1,033,417 | `38ec49e1…a69a46` |
| `tokens.txt` | 25,847 | `f536d03c…605e15` |

**Hash provenance** (checked 2026-10-09; nothing invented):
- GGUF and ONNX: Hugging Face's published LFS SHA-256 (`unsloth/Qwen3.5-2B-GGUF`, `csukuangfj/sherpa-onnx-zipformer-vi-int8-2025-04-20`).
- `tokens.txt` (not an LFS file): Hugging Face's published git blob SHA-1 (`8adf5f75…`) matches the file.

## 2. Requirements
- **Android 7.0 (API 24) or newer**, 64-bit ARM (arm64-v8a).
- **Verified on:**
  - Galaxy Tab S9 FE, Android 16 (import, chat and voice);
  - Galaxy S10, Android 12 (LLM only, September; the model import has not been run there).
- **About 1.4 GB free** for the installed models, plus 64 MB of headroom checked before each import.
- During an import, the old model stays until the new one is verified, so replacing a model temporarily needs its size again.
- The original files in Download can be deleted after a successful import, which frees 1.34 GB.
- **RAM:** about 3 GB is used while the AI model is loaded. Devices with 6 GB or more are recommended; 4 GB devices are untested.

## 3. Customer steps

The same steps go into the customer's instruction sheet.
1. Copy the three files to the device's **Download** folder (USB cable, SD card or a file-sharing app).
2. Install `halo-release.apk`; Android may ask to allow installing apps from this source.
3. Open Halo. On first start it opens **AI models** by itself. Later it's reached from **History → chip icon (AI models)**.
4. **Local AI model → Import** → choose `Qwen3.5-2B-Q4_K_M.gguf` in the file picker.
   - The progress bar runs, then it shows **Installed**. This takes seconds to tens of seconds.
5. **Vietnamese speech model → Import** → choose `halo-stt-vi.zip`. Don't unzip it. Selecting the four files together also works.
6. Go back and chat. The first voice use asks for microphone permission.

**No Internet, account or ADB is needed at any point.**

**Errors the customer may see** (every one leaves the previous model untouched):

| Message | Meaning / what to do |
|---|---|
| "That isn't the expected model file…" | The wrong file was chosen (checked by size before copying) |
| "Some speech files are missing…" | Choose the ZIP, or all four files |
| "Not enough free space: X needed, Y free" | Free up space and try again |
| "The file is damaged or a different version…" | The SHA-256 check failed after copying; copy the file to the device again |
| "The file could not be read…" | A read or write error occurred; try again |
| "Import cancelled. Nothing was changed." | The user pressed Cancel |

If the app is closed or killed during an import, the next start removes the partial copy and keeps the previous model (`ModelInstaller.recover`).

## 4. How it works (technical)

| Concern | Implementation |
|---|---|
| File access | Android **Storage Access Framework** (`ACTION_OPEN_DOCUMENT`) through a platform channel in `MainActivity.kt`. No storage permission; the release manifest has only `RECORD_AUDIO` |
| Large files | Streamed in 1 MiB blocks with SHA-256 computed while copying; the GGUF is never held in memory. The ZIP is streamed (`ZipInputStream`), and only the four needed entries are written |
| Location | App-private `getApplicationSupportDirectory()/models/` and `/stt/sherpa-onnx-zipformer-vi-int8-2025-04-20/`. These are the first paths the LLM and STT locators search, so they stay stable across restarts and updates |
| Atomicity | Staging folder `.import/<id>.staging` → verify → `rename`. The speech folder is swapped via `.import/stt.old`; `recover()` at start-up rolls back or finishes the swap and deletes staging |
| Free space | `StatFs.availableBytes` before copying (model size + 64 MB) |
| Cancel / retry | Native cancel flag checked per block; staging deleted; the import can be repeated |
| After import | The LLM and STT services are recreated, so the next use loads the new files. Chat history is untouched |
| No fake fallback | Fakes exist only under `test/`. A missing model shows "not installed yet" with a **Set up** action |
| Developer path | `/sdcard/Android/data/<pkg>/files/models` and `/stt` (ADB) still work as a fallback and are shown as "Installed (developer copy)" |

## 5. Expected timings (Galaxy Tab S9 FE, release build)

| Step | Measured |
|---|---|
| LLM import (1.28 GB, copy + SHA-256) | About 6–8 s for the copy itself: the bar was at 57% about 2.5 s after the file was chosen. 21.6 s logged including the time spent in the picker |
| Speech import (58 MB ZIP → 77 MB) | A few seconds; 11.9 s logged including the picker |
| First chat after start (model load) | 5.7 s load plus 4.6 s one-time prompt snapshot, then about 1 s to the first word for short questions |

## 6. Device acceptance (2026-10-09, Galaxy Tab S9 FE, Android 16, release build)

**Setup:**
- Evidence: [test_evidence/model_import_2026-10-09_tab_s9_fe.log](test_evidence/model_import_2026-10-09_tab_s9_fe.log).
- Before testing, the earlier test evidence was backed up to the PC.
- The developer (ADB) model copies were renamed away and restored afterwards, so the app could find **only** the imported files.
- The customer files were placed in `Download/Halo`.

| # | Check | Result |
|---|---|---|
| 1 | First start without models opens AI models; both show "Not installed" and their storage needs | **PASS** |
| 2 | Wrong file (speech ZIP chosen for the LLM) | **PASS**: rejected before copying; "That isn't the expected model file…"; *Try again* shown |
| 3 | LLM import through the system file picker (no ADB into app storage, no permission prompt) | **PASS**: 1.28 GB copied and SHA-256 verified, "Installed" |
| 4 | Cancel during a replacement | **PASS**: "Import cancelled. Nothing was changed."; the model stays installed |
| 5 | App force-stopped at 36% of a replacement, then reopened | **PASS**: no crash; the previous model is still installed. The staging cleanup itself is not observable in a release build; it is covered by unit tests |
| 6 | Speech model import from `halo-stt-vi.zip` | **PASS**: "Imported and verified." |
| 7 | Force-stop and reopen | **PASS**: opens straight into chat (models detected); the LLM loads the imported GGUF (5.7 s) and replies |
| 8 | Real Vietnamese voice → transcript → LLM reply | **PASS**: 6 voice turns, 187–329 ms from Stop to text, transcripts accurate; LLM replies at 6.8–7.9 tok/s |
| 9 | Offline | **PARTIAL**: Wi-Fi was off from 20:14:44 with no active network, and 3 full voice → LLM cycles ran then. **Airplane mode was not enabled.** The release app has no INTERNET permission |
| 10 | Insufficient storage | **NOT TESTED on device** (188 GB free; filling the device was not safe). Covered by unit tests |
| 11 | Chat history kept across the update and imports | **PASS**: existing conversations still listed |

**Observed model-quality issue (not an import problem):**
- Asked "Tháng này có bao nhiêu ngày", the LLM said 31 (correct) but invented that October 2026 is a "tháng nhuận" (leap month) and kept repeating it when corrected.
- Fixed afterwards: month length, leap years and leap months are now answered in Dart (docs/LLM_QUALITY.md §7).

## 7. Licences that must ship
- Shown in the app (History → ⓘ):
  - Apache-2.0 for the Qwen3.5-2B weights, the Vietnamese Zipformer weights and sherpa-onnx;
  - MIT for llama.cpp/ggml and ONNX Runtime;
  - BSD-3 for `record`.
- The ZIP contains `NOTICE.txt` with the speech-model attribution.
- Do **not** redistribute the sherpa-onnx release's `test_wavs/` (CC-BY-NC source).
