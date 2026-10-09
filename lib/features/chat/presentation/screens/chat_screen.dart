import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/router/app_router.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/widgets/ambient_background.dart';
import '../../../../core/widgets/content_width.dart';
import '../../../model_setup/presentation/model_setup_controller.dart';
import '../state/chat_controller.dart';
import '../state/chat_state.dart';
import '../state/composer_controller.dart';
import '../widgets/chat_body.dart';
import '../widgets/chat_header.dart';
import '../widgets/composer/chat_composer.dart';

class ChatScreen extends ConsumerWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    _listenForErrors(context, ref);
    _openSetupIfModelsMissing(context, ref);

    final isListening = ref.watch(
      composerControllerProvider.select((s) => s.voice == VoiceStatus.listening),
    );

    // Back while recording cancels the recording instead of leaving.
    return PopScope(
      canPop: !isListening,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          ref.read(composerControllerProvider.notifier).cancelListening();
        }
      },
      child: const Scaffold(
        body: AmbientBackground(
          child: SafeArea(
            bottom: false,
            child: ContentWidth(
              child: Column(
                children: [
                  ChatHeader(),
                  Expanded(child: ChatBody()),
                  ChatComposer(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _listenForErrors(BuildContext context, WidgetRef ref) {
    ref.listen(chatControllerProvider.select((s) => s.error), (_, error) {
      if (error == null) return;
      _showMessage(
        context,
        switch (error) {
          ChatError.generationFailed => AppStrings.generationFailed,
          ChatError.modelUnavailable => AppStrings.modelUnavailable,
          ChatError.loadFailed => AppStrings.loadConversationFailed,
        },
        setUp: error == ChatError.modelUnavailable,
      );
      ref.read(chatControllerProvider.notifier).clearError();
    });
    ref.listen(composerControllerProvider.select((s) => s.error),
        (_, error) {
      if (error == null) return;
      _showMessage(
        context,
        switch (error) {
          VoiceError.permissionDenied => AppStrings.micPermissionDenied,
          VoiceError.modelUnavailable => AppStrings.speechModelUnavailable,
          VoiceError.noSpeech => AppStrings.noSpeechDetected,
          VoiceError.failed => AppStrings.voiceFailed,
        },
        setUp: error == VoiceError.modelUnavailable,
      );
      ref.read(composerControllerProvider.notifier).acknowledge();
    });
  }

  static void _showMessage(
    BuildContext context,
    String message, {
    bool setUp = false,
  }) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          action: setUp
              ? SnackBarAction(
                  label: AppStrings.setUpModels,
                  onPressed: () =>
                      Navigator.of(context).pushNamed(AppRoutes.models),
                )
              : null,
        ),
      );
  }

  /// First launch without models: open Model Setup once, instead of
  /// letting the user discover it through an error.
  static void _openSetupIfModelsMissing(BuildContext context, WidgetRef ref) {
    ref.listen(modelsReadyProvider, (previous, next) {
      if (previous?.hasValue ?? false) return;
      if (next.value == false) {
        Navigator.of(context).pushNamed(AppRoutes.models);
      }
    });
  }
}
