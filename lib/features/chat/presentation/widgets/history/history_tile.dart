import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../../../app/theme/app_durations.dart';
import '../../../../../app/theme/app_radius.dart';
import '../../../../../app/theme/app_spacing.dart';
import '../../../../../core/constants/app_strings.dart';
import '../../../../../core/extensions/context_extensions.dart';
import '../../../../../core/utils/relative_date.dart';
import '../../../domain/entities/conversation_summary.dart';

/// One history row: title, one-line preview, short date.
///
/// Delete by swiping left, by long-press (action sheet), or via the
/// "Delete" accessibility action.
class HistoryTile extends StatefulWidget {
  const HistoryTile({
    super.key,
    required this.summary,
    required this.now,
    required this.isActive,
    required this.onOpen,
    required this.onDelete,
  });

  final ConversationSummary summary;
  final DateTime now;
  final bool isActive;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  State<HistoryTile> createState() => _HistoryTileState();
}

class _HistoryTileState extends State<HistoryTile>
    with SingleTickerProviderStateMixin {
  /// 1 = fully visible; animates to 0 before a long-press delete.
  late final AnimationController _presence = AnimationController(
    vsync: this,
    duration: AppDurations.medium,
    value: 1,
  );

  @override
  void dispose() {
    _presence.dispose();
    super.dispose();
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => _DeleteSheet(title: widget.summary.conversation.title),
    );
    if (confirmed != true || !mounted) return;
    await _collapseThenDelete();
  }

  Future<void> _collapseThenDelete() async {
    if (!context.reduceMotion) {
      await _presence.animateBack(0, curve: AppCurves.exit);
    }
    widget.onDelete();
  }

  @override
  Widget build(BuildContext context) {
    return SizeTransition(
      sizeFactor: _presence,
      child: FadeTransition(
        opacity: _presence,
        child: Dismissible(
          key: ValueKey('dismiss-${widget.summary.id}'),
          direction: DismissDirection.endToStart,
          onDismissed: (_) => widget.onDelete(),
          background: const _DeleteBackground(),
          child: Semantics(
            customSemanticsActions: {
              const CustomSemanticsAction(label: AppStrings.delete):
                  _collapseThenDelete,
            },
            onTapHint: AppStrings.openConversationHint,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: widget.onOpen,
                onLongPress: _confirmDelete,
                borderRadius: AppRadius.mdAll,
                child: _TileContent(
                  summary: widget.summary,
                  now: widget.now,
                  isActive: widget.isActive,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TileContent extends StatelessWidget {
  const _TileContent({
    required this.summary,
    required this.now,
    required this.isActive,
  });

  static const double _activeDot = 6;

  final ConversationSummary summary;
  final DateTime now;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final text = context.textStyles;
    final preview =
        summary.lastMessagePreview?.replaceAll(RegExp(r'\s+'), ' ').trim();
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md + AppSpacing.xxs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (isActive) ...[
                      Container(
                        width: _activeDot,
                        height: _activeDot,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: context.palette.accent,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                    ],
                    Expanded(
                      child: Text(
                        summary.conversation.title,
                        style: text.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (preview != null && preview.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    preview,
                    style: text.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Text(
            formatRelativeDay(summary.conversation.updatedAt, now: now),
            style: text.labelMedium,
          ),
        ],
      ),
    );
  }
}

class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      alignment: AlignmentDirectional.centerEnd,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      decoration: BoxDecoration(
        color: palette.dangerSurface,
        borderRadius: AppRadius.mdAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            AppStrings.delete,
            style: context.textStyles.labelLarge?.copyWith(color: palette.danger),
          ),
          const SizedBox(width: AppSpacing.sm),
          Icon(Icons.delete_outline_rounded, color: palette.danger),
        ],
      ),
    );
  }
}

class _DeleteSheet extends StatelessWidget {
  const _DeleteSheet({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = context.textStyles;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          0,
          AppSpacing.gutter,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: text.titleSmall,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpacing.lg),
            _SheetAction(
              label: AppStrings.deleteConversation,
              icon: Icons.delete_outline_rounded,
              color: palette.danger,
              background: palette.dangerSurface,
              onTap: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: AppSpacing.sm),
            _SheetAction(
              label: AppStrings.cancel,
              color: palette.textPrimary,
              background: palette.surfaceMuted,
              onTap: () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.label,
    required this.color,
    required this.background,
    required this.onTap,
    this.icon,
  });

  final String label;
  final Color color;
  final Color background;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: icon == null ? null : Icon(icon, size: AppSizes.icon),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: color,
        backgroundColor: background,
        minimumSize: const Size.fromHeight(AppSizes.minTouchTarget + AppSpacing.xs),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        textStyle: context.textStyles.labelLarge,
      ),
    );
  }
}
