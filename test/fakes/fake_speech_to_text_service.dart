import 'package:offline_ai_chat/core/error/app_exception.dart';
import 'package:offline_ai_chat/features/speech/domain/speech_to_text_service.dart';

/// Development stand-in for local speech recognition. Does not touch the
/// microphone; returns rotating canned transcripts after a short
/// "processing" delay.
class FakeSpeechToTextService implements SpeechToTextService {
  FakeSpeechToTextService({
    this.processingDelay = const Duration(milliseconds: 900),
  });

  final Duration processingDelay;

  static const List<String> _transcripts = [
    'Give me a few ideas for a relaxing weekend',
    'Explain how on-device AI works',
    'Help me write a short thank-you note',
  ];

  bool _ready = false;
  bool _listening = false;
  int _next = 0;

  @override
  bool get isReady => _ready;

  @override
  Future<void> initialize() async => _ready = true;

  @override
  Future<void> startListening() async {
    if (!_ready) {
      throw const TranscriptionException('Recognizer is not initialised.');
    }
    _listening = true;
  }

  @override
  Future<String> stopListening() async {
    if (!_listening) return '';
    _listening = false;
    await Future<void>.delayed(processingDelay);
    final transcript = _transcripts[_next % _transcripts.length];
    _next++;
    return transcript;
  }

  @override
  Future<void> cancelListening() async => _listening = false;

  @override
  Future<void> dispose() async {
    _listening = false;
    _ready = false;
  }
}
