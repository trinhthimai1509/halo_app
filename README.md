# Halo — offline AI chat

A Flutter app for iOS and Android that runs a language model **entirely
on-device**.
- **Phase 1** delivered the product foundation: architecture, design system, both screens and local persistence.
- **Phase 2** runs a real local LLM on Android: Qwen3.5-2B through llama.cpp, validated on a Galaxy S10.
- **Phase 3** adds offline Vietnamese voice input on Android: sherpa-onnx with a Zipformer model, validated on a Galaxy Tab S9 FE.

There is no backend, no analytics and no account. The release build requests
no network permission.

## Status

| Area | State |
| --- | --- |
| Chat screen (welcome state, suggestions, streaming replies, stop) | Done |
| Floating composer with voice input (30 s limit, cancel, error messages) | Done |
| History (search, open, swipe / long-press delete, empty state) | Done |
| Local persistence (SQLite) | Done |
| **Real on-device LLM, Android** (llama.cpp via `llamadart`, Qwen3.5-2B Q4_K_M) | Done; see [docs/LOCAL_AI.md](docs/LOCAL_AI.md) and [docs/LLM_BENCHMARK.md](docs/LLM_BENCHMARK.md) |
| On-device LLM and speech, iOS | Not started. iOS shows a clear "not available" message, never fake output |
| **Offline Vietnamese speech-to-text, Android** (sherpa-onnx, Zipformer-vi int8) | Done; see [docs/SPEECH.md](docs/SPEECH.md) |
| Answer quality: device date/time context, Dart calendar answers, Vietnamese system prompt, tuned sampling | Done. On-device suite 13/33 → 25/33; see [docs/LLM_QUALITY.md](docs/LLM_QUALITY.md) |
| Dark mode, localisation | Prepared, not implemented |

## Requirements

- Flutter 3.47 (stable) / Dart 3.13
- Android: Android SDK 36, JDK 17, and an **arm64** device (x86_64 for the emulator)
- The model files, installed on the device: the LLM ([docs/LOCAL_AI.md §3](docs/LOCAL_AI.md#3-development-setup-installing-the-model-on-android)) and the speech model ([docs/SPEECH.md §3](docs/SPEECH.md#3-model-installation)). Production model delivery is not decided yet.
- iOS: Xcode on macOS (not verified; built on Windows)

## Run

```bash
flutter pub get
flutter run --release                  # real LLM + speech on Android
flutter run --release --dart-define=LLM_METRICS=true  # plus [LLM]/[STT] logcat metrics
```

## Quality gates

```bash
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm64
```

Unit and widget tests use fakes from `test/fakes/`; production code has no fake path. On-device tests: the model must be installed, and always pass `--no-uninstall`, because an uninstall deletes the model.

```bash
flutter test integration_test/regression_test.dart -d <serial> --no-uninstall
flutter test integration_test/thread_sweep_test.dart -d <serial> --no-uninstall --dart-define=LLM_THREADS=2 --dart-define=LLM_SEED=42
flutter test integration_test/llm_benchmark_test.dart -d <serial> --no-uninstall
```

## Dependencies

| Package | Why |
| --- | --- |
| `flutter_riverpod` | Dependency injection plus state. Narrow rebuilds via `select`, and test overrides with no codegen. |
| `sqflite` | Local SQLite for conversations and messages (relational, cascade delete). |
| `path` | Building file paths. |
| `llamadart` **0.8.24**, pinned | llama.cpp through FFI in a worker isolate: streaming, native cancel, GGUF chat templates. It pulls in `http` transitively, for a URL loader we never call. |
| `path_provider` | Locating the model files in the app's storage folders. |
| `sherpa_onnx` **1.13.8**, pinned | Offline speech recognition (ONNX Runtime) in a worker isolate (Apache-2.0). |
| `record` | Microphone capture as 16 kHz PCM, streamed to memory (BSD-3-Clause). |
| `sqflite_common_ffi` (dev) | Runs the persistence tests against real SQLite on the host. |
| `fake_async` (dev) | Deterministic timing tests for stream coalescing. |
| `integration_test` (dev, SDK) | On-device benchmark and regression tests. |

No Firebase, analytics, routing or animation packages. Nothing contacts a server at runtime.

Licences for native runtimes and model weights (llama.cpp, ONNX Runtime, Qwen3.5-2B, the Vietnamese Zipformer) are bundled under `assets/licenses/` and shown on the in-app licence page (History → ⓘ), together with Flutter's automatic package licences.

## Project layout

```
lib/
├── main.dart                 # opens the database, starts ProviderScope
├── app/                      # composition root
│   ├── app.dart
│   ├── di/providers.dart     # which implementation backs each abstraction
│   ├── router/               # 2 named routes, platform transitions
│   └── theme/                # design system tokens + ThemeData
├── core/                     # feature-agnostic code
│   ├── constants/            # user-facing strings
│   ├── error/                # AppException hierarchy
│   ├── extensions/           # context.palette, context.reduceMotion…
│   ├── utils/                # clock, id generator, relative dates
│   └── widgets/              # AiOrb, AmbientBackground, PressableScale…
└── features/
    ├── chat/                 # conversations, messages, history
    │   ├── domain/           # entities, ChatRepository, SendMessage
    │   ├── data/             # SQLite database, data source, repository
    │   └── presentation/     # screens, widgets, Riverpod state
    ├── local_ai/             # LocalAiService boundary, llama.cpp implementation
    └── speech/               # SpeechToTextService boundary, sherpa-onnx implementation
```

## Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): layers, state, persistence, testing
- [docs/UI_DESIGN.md](docs/UI_DESIGN.md): visual direction, tokens, motion, components
- [docs/LOCAL_AI.md](docs/LOCAL_AI.md): on-device LLM runtime, model setup, lifecycle
- [docs/SPEECH.md](docs/SPEECH.md): offline Vietnamese speech-to-text, model setup, verification, limitations
- [docs/STT_SPIKE.md](docs/STT_SPIKE.md): engine and licence evaluation, spike measurements
- [docs/LLM_QUALITY.md](docs/LLM_QUALITY.md): Vietnamese answer-quality suite, root causes, before/after results
- [docs/LLM_BENCHMARK.md](docs/LLM_BENCHMARK.md): Galaxy S10 measurements and thread comparison
