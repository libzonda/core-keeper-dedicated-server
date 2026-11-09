import 'package:flutter/material.dart';
import '../theme/app_motion.dart';
import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';
import 'icon_well.dart';

/// Standard ListRow for Grouped Settings Cards
class ListRow extends StatefulWidget {
  final Widget? icon;
  final String title;
  final Widget? titleWidget;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  const ListRow({
    super.key,
    this.icon,
    this.title = '',
    this.titleWidget,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  });

  @override
  State<ListRow> createState() => _ListRowState();
}

class _ListRowState extends State<ListRow> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget rowContent = Padding(
      padding: widget.padding,
      child: Row(
        children: [
          if (widget.icon != null) ...[
            IconWell(
              icon: widget.icon!,
              size: 38,
            ),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                widget.titleWidget ??
                    Text(
                      widget.title,
                      style: AppTextStyle.body.of(
                        context,
                        emphasized: true,
                        color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                      ),
                    ),
                if (widget.subtitle != null && widget.subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    widget.subtitle!,
                    style: AppTextStyle.footnote.of(
                      context,
                      color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (widget.trailing != null) ...[
            const SizedBox(width: 12),
            widget.trailing!,
          ],
        ],
      ),
    );

    if (widget.onTap != null) {
      final inkColor = (isDark ? Colors.white : Colors.black).withValues(
        alpha: _isPressed ? 0.10 : (_isHovered ? 0.04 : 0.0),
      );

      return MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) => setState(() => _isPressed = false),
          onTapCancel: () => setState(() => _isPressed = false),
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: AppMotion.fast,
            curve: Curves.easeOutCubic,
            color: inkColor,
            child: rowContent,
          ),
        ),
      );
    }

    return rowContent;
  }
}

/// Hairline separator for grouped items
class ListRowSeparator extends StatelessWidget {
  final double indent;
  final double endIndent;

  const ListRowSeparator({
    super.key,
    this.indent = 56.0,
    this.endIndent = 16.0,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hairline = isDark ? AppColors.dividerHairlineDark : AppColors.dividerHairlineLight;

    return Padding(
      padding: EdgeInsets.only(left: indent, right: endIndent),
      child: Divider(
        height: 1,
        thickness: 1,
        color: hairline,
      ),
    );
  }
}
