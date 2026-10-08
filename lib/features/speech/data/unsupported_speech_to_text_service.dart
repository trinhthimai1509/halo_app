import '../../../core/error/app_exception.dart';
import '../domain/speech_to_text_service.dart';

/// Used on platforms without a validated offline recognizer (iOS until its
/// integration phase). Fails loudly instead of returning invented text.
class UnsupportedSpeechToTextService implements SpeechToTextService {
  const UnsupportedSpeechToTextService();

  static const _error = ModelUnavailableException(
    'Offline speech recognition is not available on this platform yet.',
  );

  @override
  bool get isReady => false;

  @override
  Future<void> initialize() => Future.error(_error);

  @override
  Future<void> startListening() => Future.error(_error);

  @override
  Future<String> stopListening() async => '';

  @override
  Future<void> cancelListening() async {}

  @override
  Future<void> dispose() async {}
}
