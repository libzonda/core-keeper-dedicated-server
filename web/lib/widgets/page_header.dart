import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';

/// Responsive Page Header
/// Gracefully adapts across desktop, tablet, and mobile displays using container constraints.
///
/// Behavior:
/// - Desktop (>= 720dp): Horizontal row with title/subtitle on left, actions on right.
/// - Tablet & Mobile (< 720dp): Stacks title on top (full width, never squished),
///   followed by actions wrapped neatly in a flexible Wrap flow.
class PageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? titleTrailing;
  final List<Widget> actions;
  final List<Widget> Function(BuildContext context, bool isCompact)? actionsBuilder;
  final Widget? bottom;

  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.titleTrailing,
    this.actions = const [],
    this.actionsBuilder,
    this.bottom,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 720;
        final isMobile = constraints.maxWidth < 480;
        final isButtonCompact = constraints.maxWidth < 960;

        final effectiveActions = actionsBuilder != null
            ? actionsBuilder!(context, isButtonCompact)
            : actions;

        final titleWidget = Text(
          title,
          style: (isMobile
                  ? AppTextStyle.title2
                  : (isCompact ? AppTextStyle.title1 : AppTextStyle.pageTitle))
              .of(
            context,
            emphasized: true,
            color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
          ),
        );

        final titleRow = titleTrailing == null
            ? titleWidget
            : Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  titleWidget,
                  titleTrailing!,
                ],
              );

        final titleAndSubtitle = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            titleRow,
            if (subtitle != null && subtitle!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: (isMobile ? AppTextStyle.caption1 : AppTextStyle.footnote).of(
                  context,
                  color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                ),
              ),
            ],
          ],
        );

        if (effectiveActions.isEmpty && bottom == null) {
          return titleAndSubtitle;
        }

        if (isCompact) {
          final compactActionsWidget = Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: effectiveActions,
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              titleAndSubtitle,
              if (effectiveActions.isNotEmpty) ...[
                const SizedBox(height: 12),
                compactActionsWidget,
              ],
              if (bottom != null) ...[
                const SizedBox(height: 12),
                bottom!,
              ],
            ],
          );
        }

        final desktopActionsWidget = Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (int i = 0; i < effectiveActions.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              effectiveActions[i],
            ],
          ],
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: titleAndSubtitle),
                if (effectiveActions.isNotEmpty) ...[
                  const SizedBox(width: 16),
                  desktopActionsWidget,
                ],
              ],
            ),
            if (bottom != null) ...[
              const SizedBox(height: 14),
              bottom!,
            ],
          ],
        );
      },
    );
  }
}
