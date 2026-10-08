import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/theme/app_durations.dart';
import '../../../../../app/theme/app_radius.dart';
import '../../../../../app/theme/app_shadows.dart';
import '../../../../../app/theme/app_spacing.dart';
import '../../../../../core/extensions/context_extensions.dart';
import '../../state/chat_controller.dart';
import '../../state/composer_controller.dart';
import 'text_composer.dart';
import 'voice_composer.dart';

/// Floating input surface. Morphs between text entry and voice capture;
/// its size animates so the transition never jumps.
class ChatComposer extends ConsumerStatefulWidget {
  const ChatComposer({super.key});

  @override
  ConsumerState<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends ConsumerState<ChatComposer> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _focus
      ..removeListener(_onFocusChanged)
      ..dispose();
    _text.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (_focused != _focus.hasFocus) setState(() => _focused = _focus.hasFocus);
  }

  void _send() {
    final text = _text.text;
    if (text.trim().isEmpty) return;
    ref.read(chatControllerProvider.notifier).send(text);
    _text.clear();
  }

  void _startVoice() {
    _focus.unfocus();
    ref.read(composerControllerProvider.notifier).startListening();
  }

  void _insertTranscript(String transcript) {
    final existing = _text.text.trimRight();
    final combined = existing.isEmpty ? transcript : '$existing $transcript';
    _text.value = TextEditingValue(
      text: combined,
      selection: TextSelection.collapsed(offset: combined.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      composerControllerProvider.select((state) => state.transcript),
      (_, transcript) {
        if (transcript == null) return;
        _insertTranscript(transcript);
        ref.read(composerControllerProvider.notifier).acknowledge();
      },
    );

    final voice =
        ref.watch(composerControllerProvider.select((state) => state.voice));
    final isGenerating =
        ref.watch(chatControllerProvider.select((state) => state.isGenerating));
    final palette = context.palette;
    final highlighted = _focused || voice != VoiceStatus.idle;

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.xs,
          AppSpacing.md,
          0,
        ),
        child: AnimatedContainer(
          duration: AppDurations.medium,
          curve: AppCurves.standard,
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: AppRadius.xlAll,
            border: Border.all(
              color: highlighted
                  ? palette.accent.withValues(alpha: 0.28)
                  : palette.hairline,
            ),
            boxShadow: highlighted
                ? AppShadows.floatingRaised(palette.shadow)
                : AppShadows.floating(palette.shadow),
          ),
          child: _SizeAnimation(
            child: AnimatedSwitcher(
              duration: AppDurations.medium,
              switchInCurve: AppCurves.emphasized,
              switchOutCurve: AppCurves.exit,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.97, end: 1).animate(animation),
                  child: child,
                ),
              ),
              child: voice == VoiceStatus.idle
                  ? TextComposer(
                      key: const ValueKey('text'),
                      controller: _text,
                      focusNode: _focus,
                      isGenerating: isGenerating,
                      onSend: _send,
                      onStop: ref.read(chatControllerProvider.notifier).stopGeneration,
                      onVoice: _startVoice,
                    )
                  : VoiceComposer(
                      key: const ValueKey('voice'),
                      status: voice,
                      onCancel: ref
                          .read(composerControllerProvider.notifier)
                          .cancelListening,
                      onFinish: ref
                          .read(composerControllerProvider.notifier)
                          .finishListening,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Animates the composer's height between modes, or snaps when Reduce
/// Motion is on. (A zero-duration AnimatedSize would re-dirty itself during
/// layout, so it is omitted rather than given Duration.zero.)
class _SizeAnimation extends StatelessWidget {
  const _SizeAnimation({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (context.reduceMotion) return child;
    return AnimatedSize(
      duration: AppDurations.slow,
      curve: AppCurves.emphasized,
      alignment: Alignment.bottomCenter,
      child: child,
    );
  }
}
