import 'package:flutter/material.dart';
import '../theme/app_motion.dart';
import '../theme/app_tokens.dart';

enum BadgeType { success, warning, error, neutral, primary }

class StatusBadge extends StatelessWidget {
  final String label;
  final BadgeType type;
  final Widget? icon;

  const StatusBadge({
    super.key,
    required this.label,
    this.type = BadgeType.neutral,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color fg;
    Color bg;

    switch (type) {
      case BadgeType.success:
        fg = isDark ? AppColors.stateSuccessDark : AppColors.stateSuccessLight;
        bg = isDark ? AppColors.stateSuccessBgDark : AppColors.stateSuccessBgLight;
        break;
      case BadgeType.warning:
        fg = isDark ? AppColors.stateWarningDark : AppColors.stateWarningLight;
        bg = isDark ? AppColors.stateWarningBgDark : AppColors.stateWarningBgLight;
        break;
      case BadgeType.error:
        fg = isDark ? AppColors.stateErrorDark : AppColors.stateErrorLight;
        bg = isDark ? AppColors.stateErrorBgDark : AppColors.stateErrorBgLight;
        break;
      case BadgeType.primary:
        fg = isDark ? AppColors.primaryDark : AppColors.primaryLight;
        bg = isDark ? const Color(0xFF003673) : const Color(0xFFD9E9FF);
        break;
      case BadgeType.neutral:
        fg = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
        bg = SurfaceLevel.inset.colorOf(context);
        break;
    }

    return AnimatedContainer(
      duration: AppMotion.base,
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: ShapeDecoration(
        color: bg,
        shape: AppShape.full,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            icon!,
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}
