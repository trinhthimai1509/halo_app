import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/providers.dart';
import '../../../../core/error/app_exception.dart';
import '../../../speech/domain/speech_to_text_service.dart';
import 'chat_controller.dart';

enum VoiceStatus { idle, listening, transcribing }

/// Why a voice session ended without a transcript.
enum VoiceError { permissionDenied, modelUnavailable, noSpeech, failed }

@immutable
class ComposerState {
  const ComposerState({
    this.voice = VoiceStatus.idle,
    this.transcript,
    this.error,
  });

  final VoiceStatus voice;

  /// A finished transcript waiting to be inserted into the text field.
  final String? transcript;

  /// One-shot: the last voice session failed or heard nothing.
  final VoiceError? error;

  bool get isVoiceActive => voice != VoiceStatus.idle;
}

final composerControllerProvider =
    NotifierProvider<ComposerController, ComposerState>(ComposerController.new);

/// Voice-input mode of the composer: idle → listening → transcribing → idle.
///
/// - Recording stops automatically after
///   [SpeechToTextService.maxRecordingDuration].
/// - Voice input does not start while the model is generating, so speech
///   recognition and LLM decoding never compete for the CPU.
///
/// The typed text itself is owned by the composer widget's
/// `TextEditingController`; only cross-widget state lives here.
class ComposerController extends Notifier<ComposerState> {
  Timer? _limit;

  /// Identifies the current session, so a stale async step (e.g. permission
  /// granted after the user already cancelled) can detect that it lost.
  int _session = 0;

  @override
  ComposerState build() {
    ref.onDispose(() => _limit?.cancel());
    return const ComposerState();
  }

  SpeechToTextService get _speech => ref.read(speechToTextServiceProvider);

  Future<void> startListening() async {
    if (state.isVoiceActive) return;
    if (ref.read(chatControllerProvider).isGenerating) return;
    final session = ++_session;
    state = const ComposerState(voice: VoiceStatus.listening);
    try {
      final speech = _speech;
      if (!speech.isReady) await speech.initialize();
      if (!_isCurrent(session)) return;
      await speech.startListening();
      if (!_isCurrent(session)) {
        // Cancelled or finished while the microphone was opening.
        await speech.cancelListening();
        return;
      }
      _limit = Timer(SpeechToTextService.maxRecordingDuration, finishListening);
    } catch (error) {
      if (ref.mounted && _isCurrent(session)) {
        state = ComposerState(error: _classify(error));
      }
    }
  }

  Future<void> finishListening() async {
    if (state.voice != VoiceStatus.listening) return;
    _limit?.cancel();
    final session = ++_session;
    state = const ComposerState(voice: VoiceStatus.transcribing);
    try {
      final transcript = (await _speech.stopListening()).trim();
      if (!ref.mounted || session != _session) return;
      state = transcript.isEmpty
          ? const ComposerState(error: VoiceError.noSpeech)
          : ComposerState(transcript: transcript);
    } catch (error) {
      if (ref.mounted && session == _session) {
        state = ComposerState(error: _classify(error));
      }
    }
  }

  Future<void> cancelListening() async {
    if (state.voice != VoiceStatus.listening) return;
    _limit?.cancel();
    _session++;
    state = const ComposerState();
    await _speech.cancelListening();
  }

  /// Marks the transcript / error as handled by the UI.
  void acknowledge() {
    if (state.transcript != null || state.error != null) {
      state = ComposerState(voice: state.voice);
    }
  }

  bool _isCurrent(int session) =>
      ref.mounted &&
      session == _session &&
      state.voice == VoiceStatus.listening;

  static VoiceError _classify(Object error) => switch (error) {
        MicrophonePermissionException() => VoiceError.permissionDenied,
        ModelUnavailableException() => VoiceError.modelUnavailable,
        _ => VoiceError.failed,
      };
}
