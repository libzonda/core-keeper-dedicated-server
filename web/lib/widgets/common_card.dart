import 'package:flutter/material.dart';
import '../theme/app_motion.dart';
import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';

/// Layered CommonCard
/// Continuous squircle surface (16dp) with contextual SurfaceScope propagation and zero borders
class CommonCard extends StatefulWidget {
  final Widget child;
  final String? title;
  final Widget? leading;
  final List<Widget>? actions;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final SurfaceLevel? level;
  final VoidCallback? onTap;

  const CommonCard({
    super.key,
    required this.child,
    this.title,
    this.leading,
    this.actions,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.level,
    this.onTap,
  });

  @override
  State<CommonCard> createState() => _CommonCardState();
}

class _CommonCardState extends State<CommonCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final effectiveLevel = widget.level ?? context.raisedSurfaceLevel;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = effectiveLevel.colorOf(context);

    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.title != null || widget.leading != null || (widget.actions != null && widget.actions!.isNotEmpty)) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: Row(
              children: [
                if (widget.leading != null) ...[
                  widget.leading!,
                  const SizedBox(width: 12),
                ],
                if (widget.title != null)
                  Expanded(
                    child: Text(
                      widget.title!,
                      style: AppTextStyle.headline.of(
                        context,
                        emphasized: true,
                        color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                      ),
                    ),
                  ),
                ...?widget.actions,
              ],
            ),
          ),
        ],
        Padding(
          padding: widget.padding,
          child: widget.child,
        ),
      ],
    );

    // Contextual propagation: children automatically advance to the next surface level
    content = SurfaceScope(
      level: effectiveLevel.next,
      child: content,
    );

    final cardShape = AppShape.md;

    if (widget.onTap != null) {
      return Padding(
        padding: widget.margin ?? EdgeInsets.zero,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: AppMotion.fast,
              curve: Curves.easeOutCubic,
              decoration: ShapeDecoration(
                color: _isHovered ? effectiveLevel.next.colorOf(context) : bgColor,
                shape: cardShape,
              ),
              child: content,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: widget.margin ?? EdgeInsets.zero,
      child: Container(
        decoration: ShapeDecoration(
          color: bgColor,
          shape: cardShape,
        ),
        child: content,
      ),
    );
  }
}
