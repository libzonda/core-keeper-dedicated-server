import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';

class SegmentTab<T> {
  final T value;
  final String title;
  final String? subtitle;
  final IconData? icon;

  const SegmentTab({
    required this.value,
    required this.title,
    this.subtitle,
    this.icon,
  });
}

/// Adaptive Adjacent-Curvature Segmented Control
/// 
/// Adjacent Tab Curvature Rules:
/// - Single tab: full stadium pill (caps on both left & right)
/// - 2 adjacent tabs:
///   - Left tab: stadium pill on left, 8dp rounded rectangle on right
///   - Right tab: 8dp rounded rectangle on left, stadium pill on right
/// - 3+ adjacent tabs:
///   - First tab: stadium pill on left, 8dp rounded rectangle on right
///   - Middle tab(s): 8dp rounded rectangle on all 4 corners
///   - Last tab: 8dp rounded rectangle on left, stadium pill on right
/// 
/// Multiline Wrapping:
/// - Naturally wraps long text into multiple lines without truncation or ellipsis
/// 
/// Motion:
/// - 250ms smooth cubic color, elevation, and style transitions
class SegmentedControl<T> extends StatelessWidget {
  final List<SegmentTab<T>> tabs;
  final T value;
  final ValueChanged<T> onChanged;
  final double? height;

  const SegmentedControl.tabs({
    super.key,
    required this.tabs,
    required this.value,
    required this.onChanged,
    this.height,
  });

  factory SegmentedControl({
    Key? key,
    required List<(T, String)> segments,
    required T value,
    required ValueChanged<T> onChanged,
    double? height,
  }) {
    return SegmentedControl.tabs(
      key: key,
      tabs: segments
          .map((s) => SegmentTab<T>(value: s.$1, title: s.$2))
          .toList(),
      value: value,
      onChanged: onChanged,
      height: height,
    );
  }

  static BorderRadius getTabBorderRadius(
    int index,
    int totalCount, {
    double pillRadius = 999.0,
    double innerRadius = 8.0,
  }) {
    if (totalCount <= 1) {
      return BorderRadius.circular(pillRadius);
    }
    if (index == 0) {
      return BorderRadius.only(
        topLeft: Radius.circular(pillRadius),
        bottomLeft: Radius.circular(pillRadius),
        topRight: Radius.circular(innerRadius),
        bottomRight: Radius.circular(innerRadius),
      );
    }
    if (index == totalCount - 1) {
      return BorderRadius.only(
        topLeft: Radius.circular(innerRadius),
        bottomLeft: Radius.circular(innerRadius),
        topRight: Radius.circular(pillRadius),
        bottomRight: Radius.circular(pillRadius),
      );
    }
    // Middle tab: fully rounded rectangle on all 4 corners
    return BorderRadius.circular(innerRadius);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final count = tabs.length;
    final primaryColor = isDark ? AppColors.primaryDark : AppColors.primaryLight;
    final unselectedBg = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA);
    final unselectedFg = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final secondaryFg = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final hasSubtitle = tabs.any((t) => t.subtitle != null && t.subtitle!.isNotEmpty);
    final effectiveHeight = height ?? (hasSubtitle ? 56.0 : 42.0);

    return Container(
      padding: const EdgeInsets.all(4.0),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E20) : const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(999.0),
      ),
      child: Row(
        children: [
          for (int i = 0; i < count; i++) ...[
            if (i > 0) const SizedBox(width: 4.0),
            Expanded(
              child: _SegmentTabItem<T>(
                tab: tabs[i],
                isSelected: tabs[i].value == value,
                borderRadius: getTabBorderRadius(i, count),
                primaryColor: primaryColor,
                unselectedBg: unselectedBg,
                unselectedFg: unselectedFg,
                secondaryFg: secondaryFg,
                minHeight: effectiveHeight,
                onTap: () => onChanged(tabs[i].value),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SegmentTabItem<T> extends StatefulWidget {
  final SegmentTab<T> tab;
  final bool isSelected;
  final BorderRadius borderRadius;
  final Color primaryColor;
  final Color unselectedBg;
  final Color unselectedFg;
  final Color secondaryFg;
  final double minHeight;
  final VoidCallback onTap;

  const _SegmentTabItem({
    required this.tab,
    required this.isSelected,
    required this.borderRadius,
    required this.primaryColor,
    required this.unselectedBg,
    required this.unselectedFg,
    required this.secondaryFg,
    required this.minHeight,
    required this.onTap,
  });

  @override
  State<_SegmentTabItem<T>> createState() => _SegmentTabItemState<T>();
}

class _SegmentTabItemState<T> extends State<_SegmentTabItem<T>> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isSelected = widget.isSelected;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color bg;
    if (isSelected) {
      bg = widget.primaryColor;
    } else if (_isHovered) {
      bg = isDark ? const Color(0xFF38383A) : const Color(0xFFDADAE0);
    } else {
      bg = widget.unselectedBg;
    }

    final fg = isSelected ? Colors.white : widget.unselectedFg;
    final subFg = isSelected
        ? Colors.white.withValues(alpha: 0.88)
        : widget.secondaryFg;

    return MouseRegion(
      cursor: isSelected ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: isSelected ? null : widget.onTap,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: _isPressed && !isSelected ? 0.75 : 1.0,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOutCubic,
            constraints: BoxConstraints(minHeight: widget.minHeight),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: widget.borderRadius,
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: widget.primaryColor.withValues(alpha: isDark ? 0.35 : 0.25),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (widget.tab.icon != null) ...[
                      Icon(
                        widget.tab.icon,
                        size: 16,
                        color: fg,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeInOut,
                        textAlign: TextAlign.center,
                        softWrap: true,
                        maxLines: 2,
                        style: AppTextStyle.subheadline.of(
                          context,
                          emphasized: isSelected,
                          color: fg,
                        ),
                        child: Text(widget.tab.title),
                      ),
                    ),
                  ],
                ),
                if (widget.tab.subtitle != null && widget.tab.subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    textAlign: TextAlign.center,
                    softWrap: true,
                    maxLines: 2,
                    style: AppTextStyle.caption2.of(
                      context,
                      color: subFg,
                    ),
                    child: Text(widget.tab.subtitle!),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
