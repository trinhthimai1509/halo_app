/// Base type for failures that cross a layer boundary.
///
/// Data sources translate platform/database errors into these so that the
/// presentation layer never depends on sqflite or a future AI runtime.
sealed class AppException implements Exception {
  const AppException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message${cause == null ? '' : ' ($cause)'}';
}

/// Reading or writing local storage failed.
final class StorageException extends AppException {
  const StorageException(super.message, [super.cause]);
}

/// The local model failed to initialise or generate.
final class GenerationException extends AppException {
  const GenerationException(super.message, [super.cause]);
}

/// The on-device model file is missing or unreadable.
final class ModelUnavailableException extends AppException {
  const ModelUnavailableException(super.message, [super.cause]);
}

/// Speech-to-text failed to start or transcribe.
final class TranscriptionException extends AppException {
  const TranscriptionException(super.message, [super.cause]);
}

/// The user has not granted microphone access.
final class MicrophonePermissionException extends AppException {
  const MicrophonePermissionException(super.message, [super.cause]);
}
