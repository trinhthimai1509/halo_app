import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/providers.dart';

enum VoiceStatus { idle, listening, transcribing }

@immutable
class ComposerState {
  const ComposerState({
    this.voice = VoiceStatus.idle,
    this.transcript,
    this.voiceFailed = false,
  });

  final VoiceStatus voice;

  /// A finished transcript waiting to be inserted into the text field.
  final String? transcript;

  /// One-shot flag: voice input could not start.
  final bool voiceFailed;

  bool get isVoiceActive => voice != VoiceStatus.idle;
}

final composerControllerProvider =
    NotifierProvider<ComposerController, ComposerState>(ComposerController.new);

/// Voice-input mode of the composer: idle → listening → transcribing → idle.
///
/// The typed text itself is owned by the composer widget's
/// `TextEditingController`; only cross-widget state lives here.
class ComposerController extends Notifier<ComposerState> {
  @override
  ComposerState build() => const ComposerState();

  Future<void> startListening() async {
    if (state.isVoiceActive) return;
    state = const ComposerState(voice: VoiceStatus.listening);
    final speech = ref.read(speechToTextServiceProvider);
    try {
      if (!speech.isReady) await speech.initialize();
      await speech.startListening();
    } catch (_) {
      if (ref.mounted) state = const ComposerState(voiceFailed: true);
    }
  }

  Future<void> finishListening() async {
    if (state.voice != VoiceStatus.listening) return;
    state = const ComposerState(voice: VoiceStatus.transcribing);
    try {
      final transcript =
          (await ref.read(speechToTextServiceProvider).stopListening()).trim();
      if (!ref.mounted) return;
      state = ComposerState(transcript: transcript.isEmpty ? null : transcript);
    } catch (_) {
      if (ref.mounted) state = const ComposerState(voiceFailed: true);
    }
  }

  Future<void> cancelListening() async {
    if (state.voice != VoiceStatus.listening) return;
    state = const ComposerState();
    await ref.read(speechToTextServiceProvider).cancelListening();
  }

  /// Marks the transcript / error as handled by the UI.
  void acknowledge() {
    if (state.transcript != null || state.voiceFailed) {
      state = ComposerState(voice: state.voice);
    }
  }
}
