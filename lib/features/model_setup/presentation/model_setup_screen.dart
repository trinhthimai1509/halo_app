import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_shadows.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/widgets/ambient_background.dart';
import '../../../core/widgets/content_width.dart';
import '../../../core/widgets/soft_icon_button.dart';
import '../data/model_catalog.dart';
import '../domain/model_package.dart';
import 'model_setup_controller.dart';

/// Shows whether the on-device models are installed and imports them from
/// files the user picks with the system file picker. No device paths are
/// shown; nothing is downloaded.
class ModelSetupScreen extends ConsumerWidget {
  const ModelSetupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(modelSetupControllerProvider);
    final textStyles = context.textStyles;
    final palette = context.palette;

    return Scaffold(
      body: AmbientBackground(
        intensity: 0.55,
        child: SafeArea(
          child: ContentWidth(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.gutter - AppSpacing.xs,
                    vertical: AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      SoftIconButton(
                        icon: Icons.arrow_back_ios_new_rounded,
                        tooltip: AppStrings.back,
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Text(
                            AppStrings.modelSetupTitle,
                            textAlign: TextAlign.center,
                            style: textStyles.titleLarge,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSizes.iconButton),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.gutter,
                      AppSpacing.sm,
                      AppSpacing.gutter,
                      AppSpacing.xxxl,
                    ),
                    children: [
                      Text(
                        AppStrings.modelSetupIntro,
                        style: textStyles.bodyMedium
                            ?.copyWith(color: palette.textSecondary),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      for (final package in ModelCatalog.all) ...[
                        _ModelCard(
                          package: package,
                          entry: entries[package.id]!,
                          hint: package == ModelCatalog.llm
                              ? AppStrings.llmModelHint
                              : AppStrings.speechModelHint,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModelCard extends ConsumerWidget {
  const _ModelCard({
    required this.package,
    required this.entry,
    required this.hint,
  });

  final ModelPackage package;
  final ModelEntryState entry;
  final String hint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final textStyles = context.textStyles;
    final controller = ref.read(modelSetupControllerProvider.notifier);
    final status = entry.status;

    final (statusText, statusColor, icon) = switch (status?.state) {
      null => (AppStrings.modelChecking, palette.textTertiary, Icons.hourglass_empty_rounded),
      ModelState.installed => (
          status!.source == ModelSource.developer
              ? AppStrings.modelInstalledDeveloper
              : AppStrings.modelInstalled,
          palette.accent,
          Icons.check_circle_rounded,
        ),
      ModelState.missing => (AppStrings.modelMissing, palette.textSecondary, Icons.download_for_offline_outlined),
      ModelState.invalid => (AppStrings.modelInvalid, palette.danger, Icons.error_outline_rounded),
    };

    final actionLabel = entry.isError
        ? AppStrings.retryAction
        : status?.state == ModelState.installed
            ? AppStrings.replaceAction
            : AppStrings.importAction;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: palette.hairline),
        boxShadow: AppShadows.soft(palette.shadow),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: statusColor, size: AppSizes.icon),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(package.title, style: textStyles.titleMedium)),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Semantics(
            liveRegion: true,
            child: Text(
              statusText,
              style: textStyles.labelLarge?.copyWith(color: statusColor),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '$hint ${AppStrings.storageNeeded(formatBytes(package.totalBytes))}.',
            style: textStyles.bodySmall?.copyWith(color: palette.textSecondary),
          ),
          if (entry.importing) ...[
            const SizedBox(height: AppSpacing.md),
            ClipRRect(
              borderRadius: AppRadius.pillAll,
              child: LinearProgressIndicator(
                value: entry.progress,
                minHeight: 6,
                color: palette.accent,
                backgroundColor: palette.surfaceMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              entry.progress == null
                  ? AppStrings.modelChecking
                  : '${(entry.progress! * 100).floor()}%',
              style: textStyles.labelMedium?.copyWith(color: palette.textSecondary),
            ),
          ],
          if (entry.message != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              entry.message!,
              style: textStyles.bodySmall?.copyWith(
                color: entry.isError ? palette.danger : palette.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerRight,
            child: entry.importing
                ? TextButton(
                    onPressed: controller.cancel,
                    child: const Text(AppStrings.cancelImport),
                  )
                : FilledButton(
                    onPressed: status == null ? null : () => controller.import(package),
                    style: FilledButton.styleFrom(
                      backgroundColor: palette.accent,
                      foregroundColor: palette.onAccent,
                    ),
                    child: Text(actionLabel),
                  ),
          ),
        ],
      ),
    );
  }
}
