import 'package:flutter/foundation.dart';

/// Roles understood by a chat-tuned local model.
enum AiRole { system, user, assistant }

/// A single turn of model context. Deliberately independent of the chat
/// feature's entities so the AI boundary has no knowledge of persistence.
@immutable
class AiMessage {
  const AiMessage({required this.role, required this.content});

  final AiRole role;
  final String content;
}

@immutable
class GenerationRequest {
  const GenerationRequest({required this.messages, this.maxTokens});

  /// Conversation context, oldest first. The implementation is responsible
  /// for applying its chat template and trimming to its context window.
  final List<AiMessage> messages;

  /// Optional upper bound on generated tokens.
  final int? maxTokens;
}

/// Boundary between the app and an on-device language model.
///
/// Implementations wrap a specific runtime (llama.cpp via FFI, a platform
/// channel to a native engine, …). Nothing above this interface may depend
/// on runtime details such as model files, FFI or method channels.
///
/// Lifecycle: [initialize] → any number of [generate] calls → [dispose].
abstract interface class LocalAiService {
  /// Whether [initialize] has completed and [generate] may be called.
  bool get isReady;

  /// Loads the model. Safe to call more than once; later calls are no-ops.
  Future<void> initialize();

  /// Streams the reply as text deltas (tokens or small chunks), in order.
  ///
  /// **Cancellation:** cancelling the stream subscription must stop
  /// generation promptly and release per-request resources.
  ///
  /// Errors are delivered as `GenerationException` stream errors.
  Stream<String> generate(GenerationRequest request);

  /// Releases the model and native resources.
  Future<void> dispose();
}
