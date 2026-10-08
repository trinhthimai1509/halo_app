import 'package:flutter/material.dart';

import '../../../../../app/theme/app_spacing.dart';
import '../../../../../core/constants/app_strings.dart';
import '../../../../../core/extensions/context_extensions.dart';
import '../../../../../core/widgets/soft_icon_button.dart';
import 'send_button.dart';

/// `[mic]  Ask anything…  [send]` — the idle composer row.
class TextComposer extends StatelessWidget {
  const TextComposer({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.isGenerating,
    required this.onSend,
    required this.onStop,
    required this.onVoice,
  });

  static const double _fieldVerticalPadding = 10;

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isGenerating;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final VoidCallback onVoice;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textStyle = context.textStyles.bodyLarge;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SoftIconButton(
            icon: Icons.mic_none_rounded,
            tooltip: AppStrings.voiceInput,
            onPressed: onVoice,
            filled: false,
          ),
          const SizedBox(width: AppSpacing.xxs),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              minLines: 1,
              maxLines: AppSizes.composerMaxLines,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              style: textStyle,
              decoration: InputDecoration(
                hintText: AppStrings.composerHint,
                hintStyle: textStyle?.copyWith(color: palette.textTertiary),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: _fieldVerticalPadding,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          // Rebuilds only the button on each keystroke.
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) => SendButton(
              mode: isGenerating
                  ? SendButtonMode.stop
                  : value.text.trim().isEmpty
                      ? SendButtonMode.disabled
                      : SendButtonMode.ready,
              onSend: onSend,
              onStop: onStop,
            ),
          ),
        ],
      ),
    );
  }
}
