import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_motion.dart';
import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';
import 'squircle_button.dart';

/// Modal Alert Dialog (348dp width, 34dp Squircle, 404ms Spring Entry)
Future<bool?> showAppDialog({
  required BuildContext context,
  required String title,
  required String content,
  String? confirmText,
  String? cancelText,
  bool isDestructive = false,
  Widget? customBody,
  double? maxWidth,
}) {
  final l10n = context.l10n;
  final effectiveConfirm = confirmText ?? l10n.confirm;
  final effectiveCancel = cancelText ?? l10n.cancel;

  return showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: AppMotion.alertDuration,
    transitionBuilder: (context, anim, _, child) {
      // 1.2x scale-in with critically damped spring
      final curvedValue = SpringCurve(AppMotion.alertSpring, seconds: 0.404).transform(anim.value);
      final scale = 1.2 - (0.2 * curvedValue);

      return Transform.scale(
        scale: scale,
        child: Opacity(
          opacity: anim.value.clamp(0.0, 1.0),
          child: child,
        ),
      );
    },
    pageBuilder: (ctx, anim, _) {
      final isDark = Theme.of(ctx).brightness == Brightness.dark;
      // In dark mode, dialog elevates to block surface for clear visual pop
      final dialogBg = isDark ? AppColors.surfaceBlockDark : AppColors.surfaceCardLight;
      final screenWidth = MediaQuery.sizeOf(ctx).width;
      final targetWidth = maxWidth ?? (customBody != null ? 440.0 : 348.0);
      final effectiveWidth = targetWidth.clamp(280.0, screenWidth - 32.0);

      return Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: effectiveWidth,
            constraints: BoxConstraints(
              maxWidth: effectiveWidth,
            ),
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            decoration: ShapeDecoration(
              color: dialogBg,
              shape: AppShape.alert, // 34dp squircle
              shadows: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.18),
                  blurRadius: 36,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: AppTextStyle.title2.of(
                    ctx,
                    emphasized: true,
                    color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                  ),
                ),
                const SizedBox(height: 12),
                if (customBody != null)
                  customBody
                else
                  Text(
                    content,
                    textAlign: TextAlign.center,
                    style: AppTextStyle.subheadline.of(
                      ctx,
                      color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                    ),
                  ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: SquircleButton(
                        variant: ButtonVariant.ghost,
                        height: 44,
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(effectiveCancel),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SquircleButton(
                        variant: isDestructive ? ButtonVariant.destructive : ButtonVariant.primary,
                        height: 44,
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(effectiveConfirm),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

