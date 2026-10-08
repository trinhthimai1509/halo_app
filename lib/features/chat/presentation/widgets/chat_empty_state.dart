import 'package:flutter/material.dart';

import '../../../../app/theme/app_durations.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/ai_orb.dart';
import 'suggestion_chips.dart';

/// Welcome area of a new conversation: orb, greeting and suggestions,
/// entering with a short stagger.
class ChatEmptyState extends StatefulWidget {
  const ChatEmptyState({super.key});

  @override
  State<ChatEmptyState> createState() => _ChatEmptyStateState();
}

class _ChatEmptyStateState extends State<ChatEmptyState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: AppDurations.entrance,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (context.reduceMotion) {
      _entrance.value = 1;
    } else {
      _entrance.forward();
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = context.textStyles;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Stagger(
                animation: _entrance,
                interval: const Interval(0, 0.6),
                child: const AiOrb(size: AppSizes.orbHero),
              ),
              const SizedBox(height: AppSpacing.xl),
              _Stagger(
                animation: _entrance,
                interval: const Interval(0.15, 0.75),
                child: Column(
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        AppStrings.welcomeTitle,
                        style: text.displaySmall,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      AppStrings.welcomeSubtitle,
                      style: text.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xxxl),
              _Stagger(
                animation: _entrance,
                interval: const Interval(0.35, 1),
                child: const SuggestionChips(),
              ),
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stagger extends StatelessWidget {
  const _Stagger({
    required this.animation,
    required this.interval,
    required this.child,
  });

  static const double _lift = 14;

  final Animation<double> animation;

  /// Portion of the parent animation this child animates over; eased with
  /// [AppCurves.enter].
  final Interval interval;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final curve = Interval(interval.begin, interval.end, curve: AppCurves.enter);
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final value = curve.transform(animation.value);
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, _lift * (1 - value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
