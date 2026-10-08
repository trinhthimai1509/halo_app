import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_ai_chat/core/error/app_exception.dart';
import 'package:offline_ai_chat/features/speech/data/audio/audio_capture.dart';
import 'package:offline_ai_chat/features/speech/data/sherpa_speech_to_text_service.dart';
import 'package:offline_ai_chat/features/speech/data/speech_recognizer.dart';

class _FakeCapture implements AudioCapture {
  bool granted = true;
  StreamController<Uint8List>? _controller;
  int starts = 0;
  int cancels = 0;
  bool disposed = false;

  @override
  int get sampleRate => 16000;

  @override
  Future<bool> hasPermission({bool request = true}) async => granted;

  @override
  Future<Stream<Uint8List>> start() async {
    starts++;
    _controller = StreamController<Uint8List>();
    return _controller!.stream;
  }

  void feed(Uint8List pcm) => _controller!.add(pcm);

  @override
  Future<void> stop() async => _controller?.close();

  @override
  Future<void> cancel() async {
    cancels++;
    await _controller?.close();
  }

  @override
  Future<void> dispose() async => disposed = true;
}

class _FakeRecognizer implements SpeechRecognizer {
  _FakeRecognizer(this.reply);

  final String reply;
  final List<int> decodedLengths = [];
  int warmUps = 0;
  bool disposed = false;
  Object? failWith;

  @override
  Future<String> transcribe(Float32List samples) async {
    if (failWith != null) throw failWith!;
    decodedLengths.add(samples.length);
    return reply;
  }

  @override
  Future<void> warmUp() async => warmUps++;

  @override
  Future<void> dispose() async => disposed = true;
}

/// [ms] of 16 kHz PCM16: a tone at [amplitude], or silence when 0.
Uint8List _pcm(int ms, double amplitude) {
  final n = 16 * ms;
  final data = ByteData(n * 2);
  for (var i = 0; i < n; i++) {
    final v = (amplitude * 32767 * math.sin(2 * math.pi * 220 * i / 16000))
        .round();
    data.setInt16(i * 2, v, Endian.little);
  }
  return data.buffer.asUint8List();
}

void main() {
  late _FakeCapture capture;
  late _FakeRecognizer recognizer;
  late int loads;

  SherpaSpeechToTextService service({Duration? max}) =>
      SherpaSpeechToTextService(
        capture: capture,
        loadRecognizer: () async {
          loads++;
          return recognizer;
        },
        maxDuration: max ?? const Duration(seconds: 30),
      );

  setUp(() {
    capture = _FakeCapture();
    recognizer = _FakeRecognizer('HÔM NAY TRỜI ĐẸP QUÁ');
    loads = 0;
  });

  test('transcribes real audio and formats the text', () async {
    final stt = service();
    await stt.initialize();
    await stt.startListening();
    capture.feed(_pcm(1500, 0.2));
    expect(await stt.stopListening(), 'Hôm nay trời đẹp quá');
    expect(recognizer.decodedLengths, hasLength(1));
  });

  test('denied permission throws MicrophonePermissionException', () async {
    capture.granted = false;
    final stt = service();
    await expectLater(
      stt.initialize(),
      throwsA(isA<MicrophonePermissionException>()),
    );
    expect(stt.isReady, isFalse);
    expect(loads, 0);
  });

  test('silence returns an empty transcript without decoding', () async {
    final stt = service();
    await stt.initialize();
    await stt.startListening();
    capture.feed(_pcm(3000, 0));
    expect(await stt.stopListening(), isEmpty);
    expect(recognizer.decodedLengths, isEmpty);
  });

  test('trims leading and trailing silence before decoding', () async {
    final stt = service();
    await stt.initialize();
    await stt.startListening();
    capture
      ..feed(_pcm(8000, 0))
      ..feed(_pcm(1000, 0.2))
      ..feed(_pcm(8000, 0));
    await stt.stopListening();
    // 1 s of speech plus padding, far less than the 17 s recorded.
    expect(recognizer.decodedLengths.single, lessThan(16000 * 2));
  });

  test('stops buffering at the maximum duration', () async {
    final stt = service(max: const Duration(seconds: 2));
    await stt.initialize();
    await stt.startListening();
    for (var i = 0; i < 5; i++) {
      capture.feed(_pcm(1000, 0.2));
    }
    await stt.stopListening();
    expect(recognizer.decodedLengths.single, lessThanOrEqualTo(2 * 16000));
  });

  test('loads the model once across sessions and warms it each session',
      () async {
    final stt = service();
    await stt.initialize();
    for (var i = 0; i < 3; i++) {
      await stt.startListening();
      capture.feed(_pcm(800, 0.2));
      await stt.stopListening();
    }
    expect(loads, 1);
    expect(recognizer.warmUps, 3);
    expect(capture.starts, 3);
  });

  test('cancel discards audio and the next session still works', () async {
    final stt = service();
    await stt.initialize();
    await stt.startListening();
    capture.feed(_pcm(800, 0.2));
    await stt.cancelListening();
    expect(capture.cancels, 1);
    expect(recognizer.decodedLengths, isEmpty);
    expect(await stt.stopListening(), isEmpty, reason: 'nothing recording');

    await stt.startListening();
    capture.feed(_pcm(800, 0.2));
    expect(await stt.stopListening(), isNotEmpty);
  });

  test('a missing model surfaces as ModelUnavailableException and is retried',
      () async {
    var installed = false;
    final stt = SherpaSpeechToTextService(
      capture: capture,
      loadRecognizer: () async {
        if (!installed) throw const ModelUnavailableException('missing');
        return recognizer;
      },
    );
    await stt.initialize();
    await stt.startListening();
    capture.feed(_pcm(800, 0.2));
    await expectLater(
      stt.stopListening(),
      throwsA(isA<ModelUnavailableException>()),
    );

    installed = true;
    await stt.startListening();
    capture.feed(_pcm(800, 0.2));
    expect(await stt.stopListening(), isNotEmpty);
  });

  test('a recognizer error becomes TranscriptionException and reloads',
      () async {
    final stt = service();
    await stt.initialize();
    recognizer.failWith = StateError('native crash');
    await stt.startListening();
    capture.feed(_pcm(800, 0.2));
    await expectLater(
      stt.stopListening(),
      throwsA(isA<TranscriptionException>()),
    );
    await Future<void>.delayed(Duration.zero);
    expect(recognizer.disposed, isTrue);

    recognizer = _FakeRecognizer('XIN CHÀO');
    await stt.startListening();
    capture.feed(_pcm(800, 0.2));
    expect(await stt.stopListening(), 'Xin chào');
    expect(loads, 2);
  });

  test('dispose frees the recognizer and the recorder', () async {
    final stt = service();
    await stt.initialize();
    await stt.startListening();
    capture.feed(_pcm(800, 0.2));
    await stt.stopListening();
    await stt.dispose();
    expect(recognizer.disposed, isTrue);
    expect(capture.disposed, isTrue);
    expect(stt.isReady, isFalse);
  });
}
