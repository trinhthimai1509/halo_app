import '../../../core/error/app_exception.dart';
import '../domain/local_ai_service.dart';

/// Used on platforms without a validated on-device runtime (iOS until its
/// integration phase). Fails loudly instead of producing canned replies.
class UnsupportedLocalAiService implements LocalAiService {
  const UnsupportedLocalAiService();

  static const _error = ModelUnavailableException(
    'On-device AI is not available on this platform yet.',
  );

  @override
  bool get isReady => false;

  @override
  Future<void> initialize() => Future.error(_error);

  @override
  Stream<String> generate(GenerationRequest request) => Stream.error(_error);

  @override
  Future<void> dispose() async {}
}
