import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_shadows.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../state/chat_controller.dart';

/// Placeholder starter prompts for development.
class _Suggestion {
  const _Suggestion(this.label, this.prompt, this.icon);

  final String label;
  final String prompt;
  final IconData icon;
}

const List<_Suggestion> _suggestions = [
  _Suggestion(
    'Explain something',
    'Explain how on-device AI works, in simple terms.',
    Icons.lightbulb_outline_rounded,
  ),
  _Suggestion(
    'Help me write',
    'Help me write a short thank-you note to a colleague.',
    Icons.edit_note_rounded,
  ),
  _Suggestion(
    'Give me ideas',
    'Give me a few ideas for a relaxing weekend.',
    Icons.auto_awesome_outlined,
  ),
  _Suggestion(
    'Ask anything',
    'What can you help me with?',
    Icons.chat_bubble_outline_rounded,
  ),
];

class SuggestionChips extends ConsumerWidget {
  const SuggestionChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm + AppSpacing.xxs,
      children: [
        for (final suggestion in _suggestions)
          _SuggestionChip(
            suggestion: suggestion,
            onTap: () =>
                ref.read(chatControllerProvider.notifier).send(suggestion.prompt),
          ),
      ],
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.suggestion, required this.onTap});

  final _Suggestion suggestion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return PressableScale(
      onTap: onTap,
      semanticLabel: suggestion.label,
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(minHeight: AppSizes.minTouchTarget),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: palette.surface.withValues(alpha: 0.85),
            borderRadius: AppRadius.pillAll,
            border: Border.all(color: palette.hairline),
            boxShadow: AppShadows.soft(palette.shadow),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(suggestion.icon, size: AppSizes.iconSmall, color: palette.accent),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  suggestion.label,
                  style: context.textStyles.labelLarge,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
