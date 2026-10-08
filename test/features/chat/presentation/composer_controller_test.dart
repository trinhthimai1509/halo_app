import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_ai_chat/core/error/app_exception.dart';
import 'package:offline_ai_chat/features/chat/presentation/state/chat_controller.dart';
import 'package:offline_ai_chat/features/chat/presentation/state/composer_controller.dart';
import 'package:offline_ai_chat/features/speech/domain/speech_to_text_service.dart';

import '../../../fakes/fake_local_ai_service.dart';
import '../../../helpers/in_memory_chat_repository.dart';
import '../../../helpers/test_overrides.dart';

/// Scriptable speech service: records calls, returns [transcript], and can
/// fail at any step.
class _ScriptedSpeech implements SpeechToTextService {
  String transcript = 'Xin chào';
  Object? initError;
  Object? stopError;
  Completer<void>? initGate;
  bool ready = false;
  bool listening = false;
  int starts = 0;
  int stops = 0;
  int cancels = 0;

  @override
  bool get isReady => ready;

  @override
  Future<void> initialize() async {
    await initGate?.future;
    if (initError != null) throw initError!;
    ready = true;
  }

  @override
  Future<void> startListening() async {
    starts++;
    listening = true;
  }

  @override
  Future<String> stopListening() async {
    stops++;
    listening = false;
    if (stopError != null) throw stopError!;
    return transcript;
  }

  @override
  Future<void> cancelListening() async {
    cancels++;
    listening = false;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  late _ScriptedSpeech speech;

  ProviderContainer createContainer({FakeLocalAiService? ai}) =>
      ProviderContainer.test(
        overrides: testOverrides(
          repository: InMemoryChatRepository(),
          ai: ai,
          speech: speech,
        ),
      );

  setUp(() => speech = _ScriptedSpeech());

  ComposerController composer(ProviderContainer c) =>
      c.read(composerControllerProvider.notifier);
  ComposerState stateOf(ProviderContainer c) =>
      c.read(composerControllerProvider);

  test('a transcript is delivered after finishing', () async {
    final c = createContainer();
    await composer(c).startListening();
    expect(stateOf(c).voice, VoiceStatus.listening);
    await composer(c).finishListening();
    expect(stateOf(c).transcript, 'Xin chào');
    expect(stateOf(c).voice, VoiceStatus.idle);
  });

  test('permission denial is reported and nothing records', () async {
    speech.initError = const MicrophonePermissionException('denied');
    final c = createContainer();
    await composer(c).startListening();
    expect(stateOf(c).error, VoiceError.permissionDenied);
    expect(stateOf(c).voice, VoiceStatus.idle);
    expect(speech.starts, 0);
  });

  test('an empty transcript is reported as no speech', () async {
    speech.transcript = '  ';
    final c = createContainer();
    await composer(c).startListening();
    await composer(c).finishListening();
    expect(stateOf(c).error, VoiceError.noSpeech);
    expect(stateOf(c).transcript, isNull);
  });

  test('a missing speech model and recognizer errors are distinguished',
      () async {
    final c = createContainer();
    speech.stopError = const ModelUnavailableException('missing');
    await composer(c).startListening();
    await composer(c).finishListening();
    expect(stateOf(c).error, VoiceError.modelUnavailable);

    composer(c).acknowledge();
    speech.stopError = const TranscriptionException('boom');
    await composer(c).startListening();
    await composer(c).finishListening();
    expect(stateOf(c).error, VoiceError.failed);
  });

  test('recording stops automatically at the maximum duration', () {
    fakeAsync((async) {
      final c = createContainer();
      composer(c).startListening();
      async.flushMicrotasks();
      expect(stateOf(c).voice, VoiceStatus.listening);

      async.elapse(
        SpeechToTextService.maxRecordingDuration - const Duration(seconds: 1),
      );
      expect(speech.stops, 0);

      async
        ..elapse(const Duration(seconds: 1))
        ..flushMicrotasks();
      expect(speech.stops, 1);
      expect(stateOf(c).transcript, 'Xin chào');
    });
  });

  test('finishing early cancels the duration limit', () {
    fakeAsync((async) {
      final c = createContainer();
      composer(c).startListening();
      async.flushMicrotasks();
      composer(c).finishListening();
      async
        ..flushMicrotasks()
        ..elapse(const Duration(minutes: 1));
      expect(speech.stops, 1);
    });
  });

  test('cancelling while the permission prompt is open never records',
      () async {
    speech.initGate = Completer<void>();
    final c = createContainer();
    final starting = composer(c).startListening();
    await composer(c).cancelListening();
    speech.initGate!.complete();
    await starting;
    expect(speech.starts, 0);
    expect(stateOf(c).voice, VoiceStatus.idle);
    expect(stateOf(c).error, isNull);
  });

  test('voice input does not start while a reply is generating', () async {
    final ai = FakeLocalAiService(
      initializationDelay: Duration.zero,
      firstChunkDelay: const Duration(milliseconds: 200),
      chunkDelay: Duration.zero,
    );
    final c = createContainer(ai: ai);
    final sending = c.read(chatControllerProvider.notifier).send('Hello');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(c.read(chatControllerProvider).isGenerating, isTrue);

    await composer(c).startListening();
    expect(stateOf(c).voice, VoiceStatus.idle);
    expect(speech.starts, 0);
    await sending;
  });

  test('repeated sessions each record once', () async {
    final c = createContainer();
    for (var i = 0; i < 3; i++) {
      await composer(c).startListening();
      await composer(c).finishListening();
      composer(c).acknowledge();
    }
    expect(speech.starts, 3);
    expect(speech.stops, 3);
    expect(speech.listening, isFalse);
  });
}
