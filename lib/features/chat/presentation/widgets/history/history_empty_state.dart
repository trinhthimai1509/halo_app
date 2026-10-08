import 'package:flutter/material.dart';

import '../../../../../app/theme/app_spacing.dart';
import '../../../../../core/constants/app_strings.dart';
import '../../../../../core/extensions/context_extensions.dart';
import '../../../../../core/widgets/ai_orb.dart';

class HistoryEmptyState extends StatelessWidget {
  const HistoryEmptyState({super.key, this.isSearchResult = false});

  /// True when the list is empty because of a search filter.
  final bool isSearchResult;

  @override
  Widget build(BuildContext context) {
    final text = context.textStyles;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AiOrb(size: AppSizes.orbEmptyHistory, animate: false),
            const SizedBox(height: AppSpacing.lg),
            Text(
              isSearchResult
                  ? AppStrings.historyNoResults
                  : AppStrings.historyEmptyTitle,
              style: text.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (!isSearchResult) ...[
              const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
              Text(
                AppStrings.historyEmptyBody,
                style: text.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
            // Keeps the content optically centred above the New chat pill.
            const SizedBox(height: AppSpacing.huge),
          ],
        ),
      ),
    );
  }
}
