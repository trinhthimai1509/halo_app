# Halo — offline AI chat

A Flutter app for iOS and Android that runs a language model **entirely
on-device**.
- **Phase 1** delivered the product foundation: architecture, design system, both screens and local persistence.
- **Phase 2** runs a real local LLM on Android: Qwen3.5-2B through llama.cpp, validated on a Galaxy S10.

There is no backend, no analytics and no account. The release build requests
no network permission.

## Status

| Area | State |
| --- | --- |
| Chat screen (welcome state, suggestions, streaming replies, stop) | Done |
| Floating composer with voice-recording states | Done (mock speech) |
| History (search, open, swipe / long-press delete, empty state) | Done |
| Local persistence (SQLite) | Done |
| **Real on-device LLM, Android** (llama.cpp via `llamadart`, Qwen3.5-2B Q4_K_M) | Done; see [docs/LOCAL_AI.md](docs/LOCAL_AI.md) and [docs/LLM_BENCHMARK.md](docs/LLM_BENCHMARK.md) |
| On-device LLM, iOS | Not started (the fake is used on iOS) |
| `SpeechToTextService` boundary + fake | Done; real STT not started |
| Dark mode, localisation | Prepared, not implemented |

## Requirements

- Flutter 3.47 (stable) / Dart 3.13
- Android: Android SDK 36, JDK 17, and an **arm64** device (x86_64 for the emulator)
- The model file, installed on the device. See [docs/LOCAL_AI.md §3](docs/LOCAL_AI.md#3-development-setup-installing-the-model-on-android).
- iOS: Xcode on macOS (not verified; built on Windows)

## Run

```bash
flutter pub get
flutter run                            # real model on Android
flutter run --dart-define=LOCAL_AI=fake  # UI work without a model
```

## Quality gates

```bash
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm64
```

On-device tests: the model must be installed, and always pass `--no-uninstall`, because an uninstall deletes the model.

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
| `path_provider` | Locating the model file in the app's storage folders. |
| `sqflite_common_ffi` (dev) | Runs the persistence tests against real SQLite on the host. |
| `fake_async` (dev) | Deterministic timing tests for stream coalescing. |
| `integration_test` (dev, SDK) | On-device benchmark and regression tests. |

No Firebase, analytics, routing or animation packages. Nothing contacts a server at runtime.

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
    ├── local_ai/             # LocalAiService boundary, llama.cpp implementation, fake
    └── speech/               # SpeechToTextService boundary + fake
```

## Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): layers, state, persistence, testing
- [docs/UI_DESIGN.md](docs/UI_DESIGN.md): visual direction, tokens, motion, components
- [docs/LOCAL_AI.md](docs/LOCAL_AI.md): on-device LLM runtime, model setup, lifecycle, STT boundary
- [docs/LLM_BENCHMARK.md](docs/LLM_BENCHMARK.md): Galaxy S10 measurements and thread comparison
