import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../../../core/error/app_exception.dart';
import '../speech_recognizer.dart';
import 'stt_model.dart';

/// sherpa-onnx offline recognizer hosted in a dedicated isolate.
///
/// `decode()` is a blocking FFI call (≈ 40 ms per second of speech on the
/// validated tablet, seconds when cold), so it never runs on the UI
/// isolate. The model is loaded once in [spawn] and reused for every call.
/// No sherpa-onnx type leaves this file.
class SherpaRecognizer implements SpeechRecognizer {
  SherpaRecognizer._(this._isolate, this._requests, this._responses);

  final Isolate _isolate;
  final SendPort _requests;
  final StreamIterator<Object?> _responses;

  Future<void> _queue = Future<void>.value();
  bool _closed = false;

  /// Upper bound for one decode. A 30 s recording decodes in ~1.2 s warm.
  static const Duration _callTimeout = Duration(seconds: 30);

  /// Loads [model] from [directory]. Throws [TranscriptionException] when
  /// the model cannot be loaded.
  static Future<SherpaRecognizer> spawn(
    String directory,
    SttModel model, {
    String? nativeLibDir,
  }) async {
    final inbox = ReceivePort();
    final responses = StreamIterator<Object?>(inbox);
    final Isolate isolate;
    try {
      isolate = await Isolate.spawn(
        _main,
        _Setup(inbox.sendPort, directory, model, nativeLibDir),
        debugName: 'stt-recognizer',
        // A crash or exit posts null, which fails the pending call.
        onExit: inbox.sendPort,
        onError: inbox.sendPort,
      );
    } catch (error) {
      inbox.close();
      throw TranscriptionException('Speech recognizer could not start.', error);
    }

    Object? next() => responses.current;
    if (!await responses.moveNext() || next() is! SendPort) {
      inbox.close();
      throw const TranscriptionException('Speech recognizer could not start.');
    }
    final requests = next()! as SendPort;
    await responses.moveNext();
    final ready = next();
    if (ready is! Map || ready['error'] != null) {
      isolate.kill();
      inbox.close();
      throw TranscriptionException(
        'Speech model could not be loaded.',
        ready is Map ? ready['error'] : ready,
      );
    }
    return SherpaRecognizer._(isolate, requests, responses);
  }

  @override
  Future<String> transcribe(Float32List samples) async {
    final reply = await _call({
      'kind': 'decode',
      'data': TransferableTypedData.fromList([samples]),
    });
    return reply['text'] as String;
  }

  @override
  Future<void> warmUp() => _call({'kind': 'warmup'});

  Future<Map<Object?, Object?>> _call(Map<String, Object?> request) {
    final result = _queue.then((_) async {
      if (_closed) {
        throw const TranscriptionException('Speech recognizer is closed.');
      }
      _requests.send(request);
      final bool hasReply;
      try {
        hasReply = await _responses.moveNext().timeout(_callTimeout);
      } on TimeoutException {
        // The iterator is still waiting; this instance cannot be reused.
        _closed = true;
        _isolate.kill(priority: Isolate.immediate);
        throw const TranscriptionException('Speech recognition timed out.');
      }
      final reply = hasReply ? _responses.current : null;
      if (reply is! Map) {
        _closed = true;
        throw TranscriptionException('Speech recognizer stopped.', reply);
      }
      if (reply['error'] != null) {
        throw TranscriptionException('Speech recognition failed.', reply['error']);
      }
      return reply;
    });
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  @override
  Future<void> dispose() async {
    if (_closed) return;
    try {
      await _call({'kind': 'free'});
    } catch (_) {
      // Already gone; killing below is enough.
    }
    _closed = true;
    await _responses.cancel();
    _isolate.kill();
  }

  // ---- worker isolate ----

  static void _main(_Setup setup) {
    final inbox = ReceivePort();
    setup.replyTo.send(inbox.sendPort);

    sherpa.OfflineRecognizer? recognizer;
    try {
      sherpa.initBindings(setup.nativeLibDir);
      final m = setup.model;
      String file(String name) => p.join(setup.directory, name);
      recognizer = sherpa.OfflineRecognizer(
        sherpa.OfflineRecognizerConfig(
          model: sherpa.OfflineModelConfig(
            transducer: sherpa.OfflineTransducerModelConfig(
              encoder: file(m.encoder),
              decoder: file(m.decoder),
              joiner: file(m.joiner),
            ),
            tokens: file(m.tokens),
            modelType: 'transducer',
            numThreads: m.threads,
            debug: false,
          ),
        ),
      );
      setup.replyTo.send(const {'ready': true});
    } catch (error) {
      setup.replyTo.send({'error': '$error'});
      inbox.close();
      return;
    }

    final silence = Float32List(setup.model.sampleRate ~/ 2);
    inbox.listen((message) {
      final request = message! as Map;
      try {
        switch (request['kind']) {
          case 'decode':
            final samples = (request['data'] as TransferableTypedData)
                .materialize()
                .asFloat32List();
            setup.replyTo.send({
              'text': _decode(recognizer!, samples, setup.model.sampleRate),
            });
          case 'warmup':
            _decode(recognizer!, silence, setup.model.sampleRate);
            setup.replyTo.send(const {'ok': true});
          case 'free':
            recognizer?.free();
            recognizer = null;
            setup.replyTo.send(const {'ok': true});
            inbox.close();
        }
      } catch (error) {
        setup.replyTo.send({'error': '$error'});
      }
    });
  }

  static String _decode(
    sherpa.OfflineRecognizer recognizer,
    Float32List samples,
    int sampleRate,
  ) {
    final stream = recognizer.createStream();
    try {
      stream.acceptWaveform(samples: samples, sampleRate: sampleRate);
      recognizer.decode(stream);
      return recognizer.getResult(stream).text;
    } finally {
      stream.free();
    }
  }
}

class _Setup {
  const _Setup(this.replyTo, this.directory, this.model, this.nativeLibDir);

  final SendPort replyTo;
  final String directory;
  final SttModel model;
  final String? nativeLibDir;
}
