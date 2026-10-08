import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/router/app_router.dart';
import '../../../../app/theme/app_durations.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/ai_orb.dart';
import '../../../../core/widgets/soft_icon_button.dart';
import '../state/chat_controller.dart';

/// Minimal header: history on the left, assistant identity centred,
/// "new chat" on the right once there is something to leave.
class ChatHeader extends ConsumerWidget {
  const ChatHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canStartNew = ref.watch(
      chatControllerProvider.select((state) => !state.isEmpty),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.gutter - AppSpacing.xs,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          SoftIconButton(
            icon: Icons.history_rounded,
            tooltip: AppStrings.openHistory,
            onPressed: () => Navigator.of(context).pushNamed(AppRoutes.history),
          ),
          const Expanded(child: _AssistantIdentity()),
          _NewChatButton(visible: canStartNew),
        ],
      ),
    );
  }
}

class _AssistantIdentity extends StatelessWidget {
  const _AssistantIdentity();

  @override
  Widget build(BuildContext context) {
    final text = context.textStyles;
    return Semantics(
      header: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const AiOrb(size: AppSizes.orbHeader, animate: false),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.appName,
                  style: text.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  AppStrings.appTagline,
                  style: text.labelSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NewChatButton extends ConsumerWidget {
  const _NewChatButton({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keeps its space when hidden so the title stays optically centred.
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: AppDurations.medium,
      curve: AppCurves.standard,
      child: AnimatedScale(
        scale: visible ? 1 : 0.85,
        duration: AppDurations.medium,
        curve: AppCurves.emphasized,
        child: IgnorePointer(
          ignoring: !visible,
          child: ExcludeSemantics(
            excluding: !visible,
            child: SoftIconButton(
              icon: Icons.edit_square,
              tooltip: AppStrings.newChat,
              onPressed: () => ref
                  .read(chatControllerProvider.notifier)
                  .startNewConversation(),
            ),
          ),
        ),
      ),
    );
  }
}
