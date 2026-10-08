import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/theme/app_durations.dart';
import '../../../../../app/theme/app_radius.dart';
import '../../../../../app/theme/app_spacing.dart';
import '../../../../../core/constants/app_strings.dart';
import '../../../../../core/extensions/context_extensions.dart';
import '../../../../../core/widgets/soft_icon_button.dart';
import '../../state/conversation_list_controller.dart';

/// "History" title with back and search actions; search expands below.
class HistoryHeader extends ConsumerStatefulWidget {
  const HistoryHeader({super.key});

  @override
  ConsumerState<HistoryHeader> createState() => _HistoryHeaderState();
}

class _HistoryHeaderState extends ConsumerState<HistoryHeader> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _searching = false;

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() => _searching = !_searching);
    if (_searching) {
      _focus.requestFocus();
    } else {
      _query.clear();
      _focus.unfocus();
      ref.read(historyQueryProvider.notifier).update('');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.gutter - AppSpacing.xs,
        vertical: AppSpacing.sm,
      ),
      child: Column(
        children: [
          Row(
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
                    AppStrings.historyTitle,
                    textAlign: TextAlign.center,
                    style: context.textStyles.titleLarge,
                  ),
                ),
              ),
              SoftIconButton(
                icon: _searching ? Icons.close_rounded : Icons.search_rounded,
                tooltip: _searching ? AppStrings.closeSearch : AppStrings.search,
                onPressed: _toggleSearch,
              ),
            ],
          ),
          AnimatedSize(
            duration: AppDurations.medium,
            curve: AppCurves.emphasized,
            child: _searching
                ? Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.md),
                    child: _SearchField(
                      controller: _query,
                      focusNode: _focus,
                      onChanged: ref.read(historyQueryProvider.notifier).update,
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final style = context.textStyles.bodyLarge;
    return TextField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      style: style,
      decoration: InputDecoration(
        hintText: AppStrings.historySearchHint,
        hintStyle: style?.copyWith(color: palette.textTertiary),
        prefixIcon: Icon(
          Icons.search_rounded,
          size: AppSizes.iconSmall,
          color: palette.textSecondary,
        ),
        filled: true,
        fillColor: palette.surface.withValues(alpha: 0.8),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        border: OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: palette.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: palette.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: palette.accent.withValues(alpha: 0.4)),
        ),
      ),
    );
  }
}
