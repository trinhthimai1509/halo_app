import 'dart:typed_data';

/// A loaded offline speech recognizer. Calls are processed one at a time.
abstract interface class SpeechRecognizer {
  /// Recognizes mono float samples in [-1, 1] at the model's sample rate.
  /// Returns the raw recognizer text (may be empty).
  Future<String> transcribe(Float32List samples);

  /// Runs a tiny decode so model pages are resident before real audio
  /// arrives (avoids a slow first decode after the OS reclaimed memory).
  Future<void> warmUp();

  /// Frees the native recognizer.
  Future<void> dispose();
}
