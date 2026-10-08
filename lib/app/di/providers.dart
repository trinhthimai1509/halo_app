import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/clock.dart';
import '../../core/utils/id_generator.dart';
import '../../features/chat/data/datasources/chat_database.dart';
import '../../features/chat/data/datasources/chat_local_data_source.dart';
import '../../features/chat/data/repositories/local_chat_repository.dart';
import '../../features/chat/domain/repositories/chat_repository.dart';
import '../../features/chat/domain/usecases/send_message.dart';
import '../../features/local_ai/data/llama_cpp/llama_cpp_local_ai_service.dart';
import '../../features/local_ai/data/unsupported_local_ai_service.dart';
import '../../features/local_ai/domain/local_ai_service.dart';
import '../../features/speech/data/sherpa_speech_to_text_service.dart';
import '../../features/speech/data/unsupported_speech_to_text_service.dart';
import '../../features/speech/domain/speech_to_text_service.dart';

// Composition root. This is the only place that knows which concrete
// implementation backs each abstraction. Tests override these providers.

final clockProvider = Provider<Clock>((ref) => DateTime.now);

final idGeneratorProvider = Provider<IdGenerator>((ref) => IdGenerator());

/// Opened asynchronously in `main()` and injected with `overrideWithValue`.
final chatDatabaseProvider = Provider<ChatDatabase>(
  (ref) => throw UnimplementedError(
    'chatDatabaseProvider must be overridden with an opened ChatDatabase.',
  ),
);

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  final repository = LocalChatRepository(
    ChatLocalDataSource(ref.watch(chatDatabaseProvider)),
  );
  ref.onDispose(repository.dispose);
  return repository;
});

/// Platforms with a validated on-device AI stack. Elsewhere the app uses
/// "unsupported" services that fail with a clear message: production code
/// never falls back to fake AI or fake speech. Fakes live under `test/`
/// and are injected by tests through provider overrides.
bool get _onDeviceAiSupported => defaultTargetPlatform == TargetPlatform.android;

/// Real on-device inference (llama.cpp). Tests override this provider.
final localAiServiceProvider = Provider<LocalAiService>((ref) {
  final LocalAiService service = _onDeviceAiSupported
      ? LlamaCppLocalAiService()
      : const UnsupportedLocalAiService();
  ref.onDispose(service.dispose);
  return service;
});

/// Real offline speech recognition (sherpa-onnx, Vietnamese). Tests
/// override this provider.
final speechToTextServiceProvider = Provider<SpeechToTextService>((ref) {
  final SpeechToTextService service = _onDeviceAiSupported
      ? SherpaSpeechToTextService()
      : const UnsupportedSpeechToTextService();
  ref.onDispose(service.dispose);
  return service;
});

final sendMessageProvider = Provider<SendMessage>(
  (ref) => SendMessage(
    repository: ref.watch(chatRepositoryProvider),
    ai: ref.watch(localAiServiceProvider),
    ids: ref.watch(idGeneratorProvider),
    clock: ref.watch(clockProvider),
  ),
);
