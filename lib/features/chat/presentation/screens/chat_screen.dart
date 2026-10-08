import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/widgets/ambient_background.dart';
import '../../../../core/widgets/content_width.dart';
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
      );
      ref.read(chatControllerProvider.notifier).clearError();
    });
    ref.listen(composerControllerProvider.select((s) => s.voiceFailed),
        (_, failed) {
      if (!failed) return;
      _showMessage(context, AppStrings.voiceFailed);
      ref.read(composerControllerProvider.notifier).acknowledge();
    });
  }

  static void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
