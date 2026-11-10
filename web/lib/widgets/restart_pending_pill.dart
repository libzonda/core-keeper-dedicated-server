import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../services/restart_state_controller.dart';
import '../theme/app_motion.dart';
import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';
import 'app_toast.dart';

class RestartPendingPill extends StatelessWidget {
  final VoidCallback? onRestartSuccess;

  const RestartPendingPill({
    super.key,
    this.onRestartSuccess,
  });

  Future<void> _handleRestart(BuildContext context) async {
    final controller = RestartStateController.instance;
    if (controller.isRestarting) return;

    controller.setRestarting(true);
    final l10n = context.l10n;

    try {
      await ApiService.instance.restartServer();
      controller.dismiss();
      onRestartSuccess?.call();

      if (context.mounted) {
        showAppToast(context, l10n.restartTriggered, type: ToastType.success);
      }
    } catch (e) {
      if (context.mounted) {
        showAppToast(context, 'Restart Failed: $e', type: ToastType.error);
      }
    } finally {
      controller.setRestarting(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: RestartStateController.instance,
      builder: (context, _) {
        final controller = RestartStateController.instance;
        final visible = controller.isRestartRequired;
        final isRestarting = controller.isRestarting;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final l10n = context.l10n;

        final warningColor = isDark ? AppColors.stateWarningDark : AppColors.stateWarningLight;
        final bgColor = isDark
            ? const Color(0xFF2C200C)
            : const Color(0xFFFFF7E6);
        final borderColor = warningColor.withValues(alpha: isDark ? 0.45 : 0.4);

        return IgnorePointer(
          ignoring: !visible,
          child: AnimatedOpacity(
            opacity: visible ? 1.0 : 0.0,
            duration: AppMotion.base,
            curve: Curves.easeInOutCubic,
            child: AnimatedScale(
              scale: visible ? 1.0 : 0.82,
              duration: AppMotion.base,
              curve: AppMotion.easeOutBack,
              alignment: Alignment.topRight,
              child: Container(
                margin: const EdgeInsets.only(top: 16, right: 24),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(AppCorner.full),
                  border: Border.all(color: borderColor, width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.1),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isRestarting)
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(warningColor),
                            ),
                          )
                        else
                          Icon(
                            Icons.restart_alt_rounded,
                            size: 16,
                            color: warningColor,
                          ),
                        const SizedBox(width: 8),
                        Tooltip(
                          message: l10n.restartPendingTooltip,
                          child: Text(
                            l10n.restartPendingPill,
                            style: AppTextStyle.subheadline.of(
                              context,
                              emphasized: true,
                              color: isDark ? const Color(0xFFFFD580) : const Color(0xFF945B00),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Quick Restart Action Pill
                        InkWell(
                          onTap: isRestarting ? null : () => _handleRestart(context),
                          borderRadius: BorderRadius.circular(AppCorner.full),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: warningColor.withValues(alpha: isDark ? 0.22 : 0.18),
                              borderRadius: BorderRadius.circular(AppCorner.full),
                            ),
                            child: Text(
                              l10n.restartNow,
                              style: AppTextStyle.caption1.of(
                                context,
                                emphasized: true,
                                color: isDark ? const Color(0xFFFFE099) : const Color(0xFF7A4B00),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        // Dismiss close button
                        InkWell(
                          onTap: isRestarting ? null : () => controller.dismiss(),
                          borderRadius: BorderRadius.circular(AppCorner.full),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.close_rounded,
                              size: 14,
                              color: warningColor.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
