import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';

enum ButtonVariant { primary, secondary, destructive, outline, ghost }

/// Stadium Pill Button with Touch Physics
/// - Perfect stadium pill shape (StadiumBorder)
/// - Flexible layout: text naturally wraps to multiple lines and widens without truncation
/// - Touch feedback: 75% opacity in light mode, +20% white glow in dark mode
class SquircleButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final Widget? child;
  final ButtonVariant variant;
  final Widget? icon;
  final bool isLoading;
  final EdgeInsetsGeometry? padding;
  final double height;
  final OutlinedBorder? shape;
  final String? tooltip;

  const SquircleButton({
    super.key,
    required this.onPressed,
    this.child,
    this.variant = ButtonVariant.secondary,
    this.icon,
    this.isLoading = false,
    this.padding,
    this.height = 40.0,
    this.shape,
    this.tooltip,
  });

  @override
  State<SquircleButton> createState() => _SquircleButtonState();
}

class _SquircleButtonState extends State<SquircleButton> with SingleTickerProviderStateMixin {
  late final AnimationController _pressController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 100),
    reverseDuration: const Duration(milliseconds: 250),
  );

  bool _isHovered = false;

  bool get _isEnabled => widget.onPressed != null && !widget.isLoading;

  void _handleTapDown(TapDownDetails _) {
    if (_isEnabled) _pressController.forward();
  }

  void _handleTapUp(TapUpDetails _) {
    if (_isEnabled) _pressController.reverse();
  }

  void _handleTapCancel() {
    if (_isEnabled) _pressController.reverse();
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color bg;
    Color fg;
    BorderSide? side;

    switch (widget.variant) {
      case ButtonVariant.primary:
        bg = isDark ? AppColors.primaryDark : AppColors.primaryLight;
        fg = Colors.white;
        break;
      case ButtonVariant.secondary:
        bg = context.raisedSurfaceLevel.colorOf(context);
        fg = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
        break;
      case ButtonVariant.destructive:
        bg = isDark ? const Color(0xFF381515) : const Color(0xFFFFECEB);
        fg = isDark ? AppColors.stateDestructiveDark : AppColors.stateDestructive;
        break;
      case ButtonVariant.outline:
        bg = Colors.transparent;
        fg = isDark ? AppColors.primaryDark : AppColors.primaryLight;
        side = BorderSide(
          color: isDark ? AppColors.dividerHairlineDark : AppColors.dividerHairlineLight,
          width: 1.0,
        );
        break;
      case ButtonVariant.ghost:
        bg = Colors.transparent;
        fg = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
        break;
    }

    if (!_isEnabled) {
      bg = bg.withValues(alpha: 0.4);
      fg = fg.withValues(alpha: 0.4);
    } else if (_isHovered && widget.variant == ButtonVariant.ghost) {
      bg = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05);
    }

    final buttonShape = widget.shape ?? (side != null ? StadiumBorder(side: side) : const StadiumBorder());

    final effectivePadding = widget.padding ??
        (widget.child == null
            ? const EdgeInsets.all(10)
            : const EdgeInsets.symmetric(horizontal: 18, vertical: 8));

    Widget button = MouseRegion(
      cursor: _isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: _handleTapDown,
        onTapUp: _handleTapUp,
        onTapCancel: _handleTapCancel,
        onTap: _isEnabled ? widget.onPressed : null,
        child: AnimatedBuilder(
          animation: _pressController,
          builder: (context, _) {
            final pressVal = _pressController.value;

            // iOS UIButton Tint/Glow Physics
            Widget buttonContent = Container(
              constraints: BoxConstraints(minHeight: widget.height),
              padding: effectivePadding,
              decoration: ShapeDecoration(
                color: bg,
                shape: buttonShape,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Dark mode: inject +20% white glow on press
                  if (isDark && pressVal > 0)
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: ShapeDecoration(
                          color: Colors.white.withValues(alpha: 0.20 * pressVal),
                          shape: buttonShape,
                        ),
                      ),
                    ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (widget.isLoading) ...[
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(fg),
                          ),
                        ),
                        if (widget.child != null) const SizedBox(width: 8),
                      ] else if (widget.icon != null) ...[
                        IconTheme(
                          data: IconThemeData(color: fg, size: 18),
                          child: widget.icon!,
                        ),
                        if (widget.child != null) const SizedBox(width: 8),
                      ],
                      if (widget.child != null)
                        Flexible(
                          child: DefaultTextStyle(
                            style: AppTextStyle.subheadline.of(
                              context,
                              emphasized: true,
                              color: fg,
                            ),
                            textAlign: TextAlign.center,
                            softWrap: true,
                            maxLines: 2,
                            child: widget.child!,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            );

            // Light mode: fade to 75% opacity on press
            if (!isDark && pressVal > 0) {
              buttonContent = Opacity(
                opacity: 1.0 - (0.25 * pressVal),
                child: buttonContent,
              );
            }

            return buttonContent;
          },
        ),
      ),
    );

    if (widget.tooltip != null && widget.tooltip!.isNotEmpty) {
      return Tooltip(
        message: widget.tooltip!,
        child: button,
      );
    }

    return button;
  }
}
