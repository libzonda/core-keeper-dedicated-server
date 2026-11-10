import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';

enum ToastType {
  info,
  success,
  warning,
  error,
}

void showAppToast(
  BuildContext context,
  String message, {
  ToastType type = ToastType.info,
  Duration duration = const Duration(seconds: 3),
  IconData? icon,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;

  final Color bg;
  final Color borderColor;
  final Color iconColor;
  final Color textColor;
  final IconData effectiveIcon;

  switch (type) {
    case ToastType.success:
      bg = isDark ? const Color(0xFF132B1A) : const Color(0xFF102416);
      borderColor = isDark ? const Color(0xFF2E7D32) : const Color(0xFF388E3C);
      iconColor = isDark ? AppColors.stateSuccessDark : const Color(0xFF66BB6A);
      textColor = const Color(0xFFF1F8F3);
      effectiveIcon = icon ?? Icons.check_circle_rounded;
      break;

    case ToastType.error:
      bg = isDark ? const Color(0xFF381416) : const Color(0xFF2E1012);
      borderColor = isDark ? const Color(0xFFB71C1C) : const Color(0xFFC62828);
      iconColor = isDark ? AppColors.stateErrorDark : const Color(0xFFEF5350);
      textColor = const Color(0xFFFFF1F1);
      effectiveIcon = icon ?? Icons.error_outline_rounded;
      break;

    case ToastType.warning:
      bg = isDark ? const Color(0xFF36240D) : const Color(0xFF2C1C0A);
      borderColor = isDark ? const Color(0xFFE65100) : const Color(0xFFEF6C00);
      iconColor = isDark ? AppColors.stateWarningDark : const Color(0xFFFFA726);
      textColor = const Color(0xFFFFF8E7);
      effectiveIcon = icon ?? Icons.warning_amber_rounded;
      break;

    case ToastType.info:
      bg = isDark ? const Color(0xFF23262D) : const Color(0xFF1A1C22);
      borderColor = isDark ? const Color(0x38FFFFFF) : const Color(0x2EFFFFFF);
      iconColor = isDark ? AppColors.primaryDark : const Color(0xFF8AB4F8);
      textColor = const Color(0xFFF4F6FA);
      effectiveIcon = icon ?? Icons.info_outline_rounded;
      break;
  }

  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      duration: duration,
      behavior: SnackBarBehavior.floating,
      backgroundColor: bg,
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: borderColor, width: 0.8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(effectiveIcon, color: iconColor, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: textColor,
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
