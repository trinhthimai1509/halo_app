import 'package:flutter/material.dart';

import '../../../../app/theme/app_durations.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/ai_orb.dart';
import '../../../../core/widgets/thinking_dots.dart';
import 'markdown_lite.dart';

/// An assistant reply, integrated into the page rather than boxed in a
/// bubble: a small identity row, then full-width readable text.
///
/// [content] is null while waiting for the first token (thinking).
class AssistantMessage extends StatelessWidget {
  const AssistantMessage({
    super.key,
    required this.content,
    this.isStreaming = false,
  });

  final String? content;
  final bool isStreaming;

  bool get _isThinking => content == null || content!.isEmpty;

  @override
  Widget build(BuildContext context) {
    final active = isStreaming || _isThinking;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Identity(active: active),
        const SizedBox(height: AppSpacing.sm),
        AnimatedSwitcher(
          duration: AppDurations.medium,
          switchInCurve: AppCurves.emphasized,
          layoutBuilder: (current, previous) => Stack(
            children: [...previous, ?current],
          ),
          child: _isThinking
              ? const Padding(
                  key: ValueKey('thinking'),
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: ThinkingDots(semanticLabel: AppStrings.thinking),
                )
              : _ReplyText(
                  key: const ValueKey('reply'),
                  content: content!,
                  showCaret: isStreaming,
                ),
        ),
      ],
    );
  }
}

class _Identity extends StatelessWidget {
  const _Identity({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Row(
        children: [
          AiOrb(
            size: AppSizes.orbAvatar,
            mode: active ? AiOrbMode.thinking : AiOrbMode.idle,
            animate: active,
          ),
          const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
          Text(AppStrings.appName, style: context.textStyles.labelMedium),
        ],
      ),
    );
  }
}

class _ReplyText extends StatelessWidget {
  const _ReplyText({super.key, required this.content, required this.showCaret});

  final String content;
  final bool showCaret;

  @override
  Widget build(BuildContext context) {
    final style = context.textStyles.bodyLarge;
    return Semantics(
      label: AppStrings.appName,
      liveRegion: showCaret,
      child: Text.rich(
        TextSpan(
          children: [
            // The model sometimes emits Markdown despite the prompt; render
            // the common subset instead of showing raw ** and #.
            ...MarkdownLite.spans(content),
            if (showCaret)
              const WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: _StreamingCaret(),
              ),
          ],
        ),
        style: style,
      ),
    );
  }
}

/// A soft pulsing dot at the end of streaming text.
class _StreamingCaret extends StatefulWidget {
  const _StreamingCaret();

  @override
  State<_StreamingCaret> createState() => _StreamingCaretState();
}

class _StreamingCaretState extends State<_StreamingCaret>
    with SingleTickerProviderStateMixin {
  static const double _size = 8;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppDurations.caretBlink,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.reduceMotion) {
      _controller.value = 1;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: AppSpacing.xs),
      child: FadeTransition(
        opacity: Tween<double>(begin: 0.3, end: 1).animate(_controller),
        child: Container(
          width: _size,
          height: _size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: palette.accentGradient,
          ),
        ),
      ),
    );
  }
}
