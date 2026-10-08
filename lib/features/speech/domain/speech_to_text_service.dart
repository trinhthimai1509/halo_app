/// Boundary for on-device speech recognition.
///
/// Implementations own microphone access and the recognition engine
/// (e.g. whisper.cpp or a platform recognizer in offline mode). Callers
/// only see a start → stop/cancel lifecycle and a final transcript.
abstract interface class SpeechToTextService {
  bool get isReady;

  /// Loads the recognizer and requests microphone permission if needed.
  /// Throws `TranscriptionException` when unavailable or permission is
  /// denied.
  Future<void> initialize();

  /// Starts capturing audio.
  Future<void> startListening();

  /// Stops capturing and returns the final transcript (may be empty).
  Future<String> stopListening();

  /// Stops capturing and discards the audio.
  Future<void> cancelListening();

  Future<void> dispose();
}
