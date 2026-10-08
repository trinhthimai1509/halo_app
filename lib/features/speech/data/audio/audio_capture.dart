import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

/// Microphone input as 16-bit little-endian mono PCM. Abstracted so the
/// speech service can be tested without a microphone.
abstract interface class AudioCapture {
  /// Sample rate of the PCM produced by [start].
  int get sampleRate;

  /// Whether microphone access is granted; asks the user when [request] is
  /// true and the platform allows it.
  Future<bool> hasPermission({bool request = true});

  /// Starts recording. The stream ends after [stop] or [cancel].
  Future<Stream<Uint8List>> start();

  Future<void> stop();

  Future<void> cancel();

  Future<void> dispose();
}

/// [AudioCapture] backed by the `record` package. Streams PCM straight to
/// memory: no file is ever written.
class RecordAudioCapture implements AudioCapture {
  RecordAudioCapture({AudioRecorder? recorder})
      : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  @override
  int get sampleRate => 16000;

  @override
  Future<bool> hasPermission({bool request = true}) =>
      _recorder.hasPermission(request: request);

  @override
  Future<Stream<Uint8List>> start() => _recorder.startStream(
        RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: sampleRate,
          numChannels: 1,
          // Speech-tuned input path, no echo cancellation or AGC applied
          // on top (validated in the STT spike).
          androidConfig: const AndroidRecordConfig(
            audioSource: AndroidAudioSource.voiceRecognition,
          ),
        ),
      );

  @override
  Future<void> stop() async {
    await _recorder.stop();
  }

  @override
  Future<void> cancel() => _recorder.cancel();

  @override
  Future<void> dispose() => _recorder.dispose();
}
