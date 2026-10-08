import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/clock.dart';
import '../../core/utils/id_generator.dart';
import '../../features/chat/data/datasources/chat_database.dart';
import '../../features/chat/data/datasources/chat_local_data_source.dart';
import '../../features/chat/data/repositories/local_chat_repository.dart';
import '../../features/chat/domain/repositories/chat_repository.dart';
import '../../features/chat/domain/usecases/send_message.dart';
import '../../features/local_ai/data/fake_local_ai_service.dart';
import '../../features/local_ai/data/llama_cpp/llama_cpp_local_ai_service.dart';
import '../../features/local_ai/domain/local_ai_service.dart';
import '../../features/speech/data/fake_speech_to_text_service.dart';
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

/// `--dart-define=LOCAL_AI=fake` forces the fake model (UI work without a
/// model installed); `LOCAL_AI=llama` forces llama.cpp.
const String _localAiOverride = String.fromEnvironment('LOCAL_AI');

/// Real on-device inference (llama.cpp) on Android. Other platforms keep the
/// fake until their runtime integration phase. Tests override this provider.
final localAiServiceProvider = Provider<LocalAiService>((ref) {
  final useLlama = switch (_localAiOverride) {
    'fake' => false,
    'llama' => true,
    _ => defaultTargetPlatform == TargetPlatform.android,
  };
  final LocalAiService service =
      useLlama ? LlamaCppLocalAiService() : FakeLocalAiService();
  ref.onDispose(service.dispose);
  return service;
});

final speechToTextServiceProvider = Provider<SpeechToTextService>((ref) {
  final service = FakeSpeechToTextService();
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
