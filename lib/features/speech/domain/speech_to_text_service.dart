/// Boundary for on-device speech recognition.
///
/// Implementations own microphone access and the recognition engine.
/// Callers only see a start → stop/cancel lifecycle and a final transcript.
/// Audio never leaves the implementation and is not persisted.
abstract interface class SpeechToTextService {
  /// Longest recording a caller should allow. Implementations also stop
  /// buffering audio beyond this point.
  static const Duration maxRecordingDuration = Duration(seconds: 30);

  bool get isReady;

  /// Requests microphone permission if needed and starts preparing the
  /// recognizer in the background (it may still be loading when this
  /// returns). Throws `MicrophonePermissionException` when permission is
  /// denied.
  Future<void> initialize();

  /// Starts capturing audio. Requires a successful [initialize].
  Future<void> startListening();

  /// Stops capturing and returns the final transcript, or an empty string
  /// when no speech was detected. Throws `ModelUnavailableException` when
  /// the recognizer model is missing and `TranscriptionException` when
  /// recognition fails.
  Future<String> stopListening();

  /// Stops capturing and discards the audio.
  Future<void> cancelListening();

  Future<void> dispose();
}
