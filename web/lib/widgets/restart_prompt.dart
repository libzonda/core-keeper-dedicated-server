import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';
import 'app_dialog.dart';
import 'app_toast.dart';

/// Checks if server is running, and if so, prompts user to restart the server
/// so that the latest configuration, world changes, or mod adjustments take effect.
Future<void> checkAndPromptRestart(
  BuildContext context, {
  required String title,
  required String reason,
  VoidCallback? onRestartTriggered,
}) async {
  try {
    final status = await ApiService.instance.getStatus();
    if (!status.isRunning) return;
    if (!context.mounted) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = context.l10n;

    final restart = await showAppDialog(
      context: context,
      title: title,
      content: '',
      confirmText: l10n.restartNow,
      cancelText: l10n.restartLater,
      customBody: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            reason,
            style: AppTextStyle.subheadline.of(context),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: ShapeDecoration(
              color: isDark ? AppColors.stateWarningBgDark : AppColors.stateWarningBgLight,
              shape: AppShape.sm,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: isDark ? AppColors.stateWarningDark : AppColors.stateWarningLight,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.restartPromptNotice,
                    style: AppTextStyle.footnote.of(
                      context,
                      color: isDark ? AppColors.stateWarningDark : AppColors.stateWarningLight,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (restart == true && context.mounted) {
      await ApiService.instance.restartServer();
      onRestartTriggered?.call();
      if (context.mounted) {
        showAppToast(context, l10n.restartTriggered, type: ToastType.success);
      }
    }
  } catch (_) {}
}
