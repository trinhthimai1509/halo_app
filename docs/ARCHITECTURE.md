# Architecture

Feature-first Clean Architecture, applied pragmatically: a layer or
abstraction exists only where it buys testability or a real seam for a
future change.

## Layers

```
presentation (widgets, Riverpod notifiers)
        │ depends on
        ▼
domain (entities, ChatRepository, SendMessage, LocalAiService, SpeechToTextService)
        ▲ implemented by
        │
data (SQLite data source, LocalChatRepository, FakeLocalAiService, FakeSpeechToTextService)
```

- **Domain** is plain Dart plus `package:flutter/foundation.dart` for
  `@immutable`. No sqflite, no widgets.
- **Data** implements domain interfaces and translates failures into
  `AppException` subtypes (`StorageException`, `GenerationException`,
  `TranscriptionException`).
- **Presentation** talks to domain types only. Concrete implementations are
  chosen in one place: `lib/app/di/providers.dart`.

### Features

| Feature | Why it is separate |
| --- | --- |
| `chat` | Conversations, messages and history. History is not split into its own feature because it shares the same entities, repository and state. |
| `local_ai` | The on-device model boundary. It knows nothing about chat persistence (`AiMessage` is its own type) so a runtime can be integrated and tested in isolation. Phase 2 added `LlamaCppLocalAiService` (llama.cpp via llamadart, the only file importing it), `ContextWindowPolicy` and `StreamCoalescer`; see LOCAL_AI.md. Model download / management UI will live here. |
| `speech` | The on-device speech-to-text boundary. |

## Use cases

There is one use case, `SendMessage`, because sending a message has real
orchestration:

1. create the conversation on the first message (title derived from the prompt),
2. persist the user message,
3. initialise the model if needed and stream the reply,
4. persist the reply — including a *partial* reply if the user stops
   generation or the model fails mid-stream.

It returns a `Stream<SendMessageEvent>`
(`UserMessageSaved → ReplyStarted → ReplyChunk* → ReplyCompleted`).
Cancelling the subscription cancels generation; the use case's `finally`
block persists what was already streamed, so history always matches what the
user saw.

Listing, opening and deleting conversations are single repository calls, so
the notifiers call the repository directly. Wrapping them in pass-through use
case classes would add files without adding meaning.

## State management — Riverpod 3

Why Riverpod:

- compile-safe dependency injection and state in one tool. No `BuildContext`
  lookups, no global singletons.
- `ProviderContainer.test(overrides: …)` swaps the repository, AI and clock
  in tests without mocking frameworks.
- `select` keeps rebuilds narrow, which matters while tokens stream in.
- It needs no code generation, so there is no build_runner step.

State ownership:

| Provider | Owns | Lifetime |
| --- | --- | --- |
| `chatControllerProvider` (`Notifier<ChatState>`) | The open conversation: messages, the streaming draft, generation status (idle / thinking / streaming), loading, one-shot errors | App |
| `conversationListProvider` (`StreamNotifier<List<ConversationSummary>>`) | History. Reacts to `ChatRepository.watchConversations()` and does optimistic deletion | App |
| `historyQueryProvider` + `filteredConversationsProvider` | History search text and the filtered view | Auto-dispose (reset when History closes) |
| `composerControllerProvider` (`Notifier<ComposerState>`) | Voice input mode (idle / listening / transcribing) and the finished transcript | App |

Typed text is deliberately not in a provider. The composer widget owns its
`TextEditingController`, because that is ephemeral UI state.

Cross-controller coordination is explicit and one-directional:
`ConversationListController.delete` first asks
`ChatController.closeIfActive`, so a reply that is still streaming is never
written into a conversation that has just been deleted.

### Rebuild strategy while streaming

- `MessageList` watches only `messages` and `isGenerating`.
- `StreamingReply` is the only widget that watches `streamingReply.content`.
- The send button rebuilds from the text controller via
  `ValueListenableBuilder`, not on every keystroke of the whole composer.
- The orb repaints through a `CustomPainter` bound to its controller, with
  no widget rebuilds, inside a `RepaintBoundary`.

## Persistence — SQLite via sqflite

Why SQLite: conversations and messages are relational. Ordered queries,
"last message per conversation" and cascade delete are natural in SQL.
sqflite is mature on iOS and Android and needs no code generation.

Schema (version 1):

```sql
conversations(id TEXT PK, title TEXT, created_at INT, updated_at INT)
messages(id TEXT PK,
         conversation_id TEXT REFERENCES conversations(id) ON DELETE CASCADE,
         role TEXT, content TEXT, created_at INT)
INDEX messages(conversation_id, created_at)
INDEX conversations(updated_at DESC)
```

- Timestamps are stored as microseconds since the epoch. Messages created
  in the same microsecond keep insertion order via `rowid`.
- `PRAGMA foreign_keys = ON` is set in `onConfigure`, so the cascade works.
- `addMessage` inserts the message and bumps `conversations.updated_at` in
  one transaction.
- The domain entities (`Conversation`, `ChatMessage`) are independent of the
  row mappers (`ConversationRecord`, `MessageRecord`).
- `LocalChatRepository.watchConversations()` re-queries after every write
  made through the repository. That is enough for a single-process app with
  no external writers.
- Migrations: bump `ChatDatabase.schemaVersion` and add `onUpgrade`.

## Navigation

Two routes (`/` chat and `/history`) through `onGenerateRoute`. A routing
package isn't justified for two routes. `MaterialPageRoute` takes its
transitions from the theme:

- iOS: `CupertinoPageTransitionsBuilder`, which keeps the native edge
  swipe-back.
- Android: `PredictiveBackPageTransitionsBuilder`. This gives predictive
  back (enabled in the manifest) and the fade-forwards transition otherwise.

On the chat screen, back while recording cancels the recording (`PopScope`)
instead of leaving the app.

## Testing

| Test | What it proves |
| --- | --- |
| `fake_local_ai_service_test` | Progressive multi-chunk streaming, the initialisation contract, cancellation stopping the stream, dispose |
| `chat_controller_test` | Sending creates a conversation, streams through thinking → streaming, and persists both turns. The same conversation is continued. Blank input is ignored. Stop keeps and persists the partial reply. Open, new chat, missing conversation, and deleting the active conversation |
| `local_chat_repository_test` | Against real SQLite (FFI) and a real file: data survives closing and reopening, ordering and preview, cascade delete, change notifications |
| `chat_screen_test` | Welcome state, suggestion → streamed reply, typing and sending, voice finish/cancel, small phone at 1.6× text without overflow |
| `history_screen_test` | Empty state, list order, preview and relative dates, reopening, swipe delete, long-press delete, search |
| `conversation_title_test` | Title derivation and relative-date formatting |
| `send_message_test` | The system prompt, history and new message reach the model in order |
| `context_window_policy_test` | Trimming the oldest turns first, always keeping the system prompt and current turn, and rejecting over-long input |
| `stream_coalescer_test` | First piece emitted immediately, then batched per 50 ms; flush and dispose |

On-device tests in `integration_test/` use the real model and are **not** part of `flutter test`:
- `regression_test.dart`: completion then next, Stop then next with a native CPU check, repeated and bounded sustained generation.
- `thread_sweep_test.dart`: the controlled decode-thread comparison.
- `llm_benchmark_test.dart`: the 7-prompt Vietnamese and English set.

See LOCAL_AI.md and LLM_BENCHMARK.md.

Widget tests run with Reduce Motion enabled
(`FakeAccessibilityFeatures(disableAnimations: true)`). This stops the looping
decorative animations so `pumpAndSettle` completes, and it exercises the
accessibility path.
