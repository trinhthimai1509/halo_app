import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// One recognition result from the worker isolate.
class SttResult {
  const SttResult({required this.text, required this.decodeMs});

  final String text;

  /// Feature extraction + decode time inside the worker (excludes isolate
  /// messaging).
  final int decodeMs;
}

/// Hosts a sherpa-onnx [sherpa.OfflineRecognizer] in a dedicated isolate.
///
/// `decode()` is a blocking FFI call (hundreds of ms on a phone), so it must
/// never run on the UI isolate. The recognizer is loaded once and reused.
class SttWorker {
  SttWorker._(this._isolate, this._requests, this._responses, this.loadMs);

  final Isolate _isolate;
  final SendPort _requests;
  final StreamIterator<Object?> _responses;

  /// Time to create the recognizer (model load) inside the worker.
  final int loadMs;

  Future<void> _pending = Future<void>.value();

  /// Loads the Zipformer transducer from [modelDir] (expects the file names
  /// of `sherpa-onnx-zipformer-vi-int8-2025-04-20`).
  /// [nativeLibDir] is only for host (desktop/test) runs; on Android the
  /// plugin's bundled library is found automatically.
  static Future<SttWorker> spawn(
    String modelDir, {
    int threads = 2,
    String? nativeLibDir,
  }) async {
    final inbox = ReceivePort();
    final isolate = await Isolate.spawn(
      _main,
      [inbox.sendPort, modelDir, threads, nativeLibDir],
      debugName: 'stt-worker',
    );
    final responses = StreamIterator<Object?>(inbox);
    await responses.moveNext();
    final requests = responses.current! as SendPort;
    await responses.moveNext();
    final ready = responses.current! as Map;
    if (ready['error'] != null) {
      isolate.kill();
      throw StateError('STT load failed: ${ready['error']}');
    }
    return SttWorker._(isolate, requests, responses, ready['loadMs'] as int);
  }

  /// Recognizes 16 kHz mono float samples in [-1, 1].
  Future<SttResult> transcribe(Float32List samples) => _call({
        'kind': 'samples',
        'data': TransferableTypedData.fromList([samples]),
      });

  /// Recognizes a 16-bit PCM WAV file (control case, no microphone).
  Future<SttResult> transcribeFile(String path) =>
      _call({'kind': 'file', 'path': path});

  Future<SttResult> _call(Map<String, Object?> request) {
    final result = _pending.then((_) async {
      _requests.send(request);
      await _responses.moveNext();
      final reply = _responses.current! as Map;
      if (reply['error'] != null) throw StateError('${reply['error']}');
      return SttResult(
        text: reply['text'] as String,
        decodeMs: reply['decodeMs'] as int,
      );
    });
    _pending = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Frees the native recognizer and ends the isolate.
  Future<void> dispose() async {
    await _pending;
    _requests.send({'kind': 'free'});
    await _responses.moveNext();
    await _responses.cancel();
    _isolate.kill();
  }

  static void _main(List<Object?> args) {
    final replyTo = args[0]! as SendPort;
    final modelDir = args[1]! as String;
    final threads = args[2]! as int;
    final nativeLibDir = args[3] as String?;
    final inbox = ReceivePort();
    replyTo.send(inbox.sendPort);

    sherpa.OfflineRecognizer? recognizer;
    try {
      sherpa.initBindings(nativeLibDir);
      final watch = Stopwatch()..start();
      recognizer = sherpa.OfflineRecognizer(
        sherpa.OfflineRecognizerConfig(
          model: sherpa.OfflineModelConfig(
            transducer: sherpa.OfflineTransducerModelConfig(
              encoder: '$modelDir/encoder-epoch-12-avg-8.int8.onnx',
              decoder: '$modelDir/decoder-epoch-12-avg-8.onnx',
              joiner: '$modelDir/joiner-epoch-12-avg-8.int8.onnx',
            ),
            tokens: '$modelDir/tokens.txt',
            modelType: 'transducer',
            numThreads: threads,
            debug: false,
          ),
        ),
      );
      replyTo.send({'loadMs': watch.elapsedMilliseconds});
    } catch (error) {
      replyTo.send({'error': '$error'});
      inbox.close();
      return;
    }

    inbox.listen((message) {
      final request = message as Map;
      try {
        switch (request['kind']) {
          case 'free':
            recognizer?.free();
            recognizer = null;
            replyTo.send({'freed': true});
            inbox.close();
          case 'samples':
            final data = (request['data'] as TransferableTypedData)
                .materialize()
                .asFloat32List();
            replyTo.send(_decode(recognizer!, data, 16000));
          case 'file':
            final wave = sherpa.readWave(request['path'] as String);
            if (wave.sampleRate == 0) {
              throw StateError('Cannot read ${request['path']}');
            }
            replyTo.send(_decode(recognizer!, wave.samples, wave.sampleRate));
        }
      } catch (error) {
        replyTo.send({'error': '$error'});
      }
    });
  }

  static Map<String, Object> _decode(
    sherpa.OfflineRecognizer recognizer,
    Float32List samples,
    int sampleRate,
  ) {
    final watch = Stopwatch()..start();
    final stream = recognizer.createStream();
    try {
      stream.acceptWaveform(samples: samples, sampleRate: sampleRate);
      recognizer.decode(stream);
      final text = recognizer.getResult(stream).text;
      return {'text': text, 'decodeMs': watch.elapsedMilliseconds};
    } finally {
      stream.free();
    }
  }
}
