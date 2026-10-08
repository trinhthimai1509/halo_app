import 'dart:async';
import 'dart:typed_data';

import '../../../core/error/app_exception.dart';
import '../domain/speech_to_text_service.dart';
import '../domain/transcript_formatter.dart';
import 'audio/audio_capture.dart';
import 'audio/audio_signal.dart';
import 'sherpa/sherpa_recognizer.dart';
import 'sherpa/stt_model.dart';
import 'speech_recognizer.dart';
import 'stt_metrics.dart';

/// Loads a [SpeechRecognizer]; injectable for tests.
typedef RecognizerLoader = Future<SpeechRecognizer> Function();

/// Offline speech-to-text: microphone → in-memory PCM → sherpa-onnx
/// Vietnamese Zipformer → readable transcript.
///
/// - **Lazy, single load.** The recognizer is created on the first
///   [initialize] (in the background) and reused until [dispose]. A failed
///   load is retried on the next session.
/// - **Cold start hidden behind speech.** Loading (~2.4 s) and a warm-up
///   decode run while the user is still talking; [stopListening] only waits
///   for whatever is left.
/// - **Audio stays in memory.** PCM is buffered in RAM, capped at
///   [maxDuration], and dropped as soon as it has been decoded or cancelled.
/// - **Fully offline.** Model files are read from local storage; nothing
///   here can reach the network (the release app has no INTERNET
///   permission).
class SherpaSpeechToTextService implements SpeechToTextService {
  SherpaSpeechToTextService({
    AudioCapture? capture,
    RecognizerLoader? loadRecognizer,
    this.maxDuration = SpeechToTextService.maxRecordingDuration,
  })  : _capture = capture ?? RecordAudioCapture(),
        _loadRecognizer = loadRecognizer ?? _loadVietnamese;

  final AudioCapture _capture;
  final RecognizerLoader _loadRecognizer;
  final Duration maxDuration;

  Future<SpeechRecognizer>? _recognizer;
  bool _permissionGranted = false;
  bool _disposed = false;

  // Current recording, null when idle. Cancelled in _releaseRecording.
  // ignore: cancel_subscriptions
  StreamSubscription<Uint8List>? _audio;
  BytesBuilder? _pcm;
  Completer<void>? _audioDone;
  Object? _captureError;

  int get _maxBytes =>
      _capture.sampleRate * 2 * maxDuration.inMilliseconds ~/ 1000;

  static Future<SpeechRecognizer> _loadVietnamese() async {
    const model = SttModel.vietnamese;
    const locator = SttModelLocator();
    final directory = await locator.find(model);
    if (directory == null) {
      final expected = await locator.candidateDirectories(model);
      throw ModelUnavailableException(
        'Speech model ${model.directoryName} is not installed. '
        'Expected at: ${expected.join(' or ')}',
      );
    }
    final watch = Stopwatch()..start();
    final recognizer = await SherpaRecognizer.spawn(directory, model);
    SttMetrics.log('model_loaded', {
      'model': model.directoryName,
      'threads': model.threads,
      'load_ms': watch.elapsedMilliseconds,
    });
    return recognizer;
  }

  @override
  bool get isReady => _permissionGranted && !_disposed;

  @override
  Future<void> initialize() async {
    _ensureNotDisposed();
    if (!await _capture.hasPermission()) {
      throw const MicrophonePermissionException(
        'Microphone permission was denied.',
      );
    }
    _permissionGranted = true;
    // Start loading now; errors resurface from stopListening().
    unawaited(_ensureRecognizer().then((_) {}, onError: (_) {}));
  }

  @override
  Future<void> startListening() async {
    _ensureNotDisposed();
    if (!_permissionGranted) {
      throw const TranscriptionException('Recognizer is not initialised.');
    }
    if (_audio != null) return;

    final Stream<Uint8List> stream;
    try {
      stream = await _capture.start();
    } catch (error) {
      throw TranscriptionException('The microphone could not be opened.', error);
    }
    final pcm = BytesBuilder(copy: false);
    final done = Completer<void>();
    final maxBytes = _maxBytes;
    _pcm = pcm;
    _audioDone = done;
    _captureError = null;
    _audio = stream.listen(
      (chunk) {
        final room = maxBytes - pcm.length;
        if (room <= 0) return;
        pcm.add(chunk.length <= room ? chunk : Uint8List.sublistView(chunk, 0, room));
      },
      onError: (Object error) => _captureError = error,
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
    );

    // Bring the model in (or back) while the user speaks.
    unawaited(
      _ensureRecognizer()
          .then((recognizer) => recognizer.warmUp())
          .then((_) {}, onError: (_) {}),
    );
  }

  @override
  Future<String> stopListening() async {
    final audio = _audio;
    if (audio == null) return '';
    final stoppedAt = Stopwatch()..start();
    try {
      await _capture.stop();
    } catch (_) {
      // Fall through: whatever was buffered is still usable.
    }
    await _audioDone!.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () {},
    );
    final bytes = _releaseRecording(audio).takeBytes();

    if (_captureError != null) {
      throw TranscriptionException('Recording failed.', _captureError);
    }

    final samples = AudioSignal.pcm16ToFloat32(bytes);
    final audioMs = samples.length * 1000 ~/ _capture.sampleRate;
    final speech =
        AudioSignal.trimSilence(samples, sampleRate: _capture.sampleRate);
    if (speech == null) {
      SttMetrics.log('no_speech', {
        'audio_ms': audioMs,
        'peak': AudioSignal.peak(samples).toStringAsFixed(3),
      });
      return '';
    }

    final recognizer = await _ensureRecognizer();
    final decodeWatch = Stopwatch()..start();
    final String raw;
    try {
      raw = await recognizer.transcribe(speech);
    } on AppException {
      _discardRecognizer();
      rethrow;
    } catch (error) {
      _discardRecognizer();
      throw TranscriptionException('Speech recognition failed.', error);
    }
    final text = TranscriptFormatter.format(raw);
    SttMetrics.log('transcribed', {
      'audio_ms': audioMs,
      'speech_ms': speech.length * 1000 ~/ _capture.sampleRate,
      'peak': AudioSignal.peak(samples).toStringAsFixed(3),
      'decode_ms': decodeWatch.elapsedMilliseconds,
      'stop_to_text_ms': stoppedAt.elapsedMilliseconds,
      'text': '"$text"',
    });
    return text;
  }

  @override
  Future<void> cancelListening() async {
    final audio = _audio;
    if (audio == null) return;
    try {
      await _capture.cancel();
    } catch (_) {
      // The buffer is discarded either way.
    }
    _releaseRecording(audio).clear();
    SttMetrics.log('cancelled', const {});
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final audio = _audio;
    if (audio != null) _releaseRecording(audio).clear();
    await _capture.dispose();
    final recognizer = _recognizer;
    _recognizer = null;
    if (recognizer != null) {
      try {
        await (await recognizer).dispose();
      } catch (_) {
        // Never loaded; nothing to free.
      }
    }
  }

  /// Detaches the current recording and returns its buffer for one last
  /// read. After this the service holds no reference to the audio.
  BytesBuilder _releaseRecording(StreamSubscription<Uint8List> audio) {
    unawaited(audio.cancel());
    final pcm = _pcm!;
    _audio = null;
    _pcm = null;
    _audioDone = null;
    return pcm;
  }

  Future<SpeechRecognizer> _ensureRecognizer() {
    final existing = _recognizer;
    if (existing != null) return existing;
    final loading = _loadRecognizer();
    _recognizer = loading;
    loading.then(
      (recognizer) {
        // Disposed while loading: free it right away.
        if (_disposed) recognizer.dispose();
      },
      onError: (_) {
        // Allow a retry on the next session.
        if (identical(_recognizer, loading)) _recognizer = null;
      },
    );
    return loading;
  }

  void _discardRecognizer() {
    final broken = _recognizer;
    _recognizer = null;
    broken?.then((r) => r.dispose(), onError: (_) {});
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw const TranscriptionException('Speech service was disposed.');
    }
  }
}
