import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/instance_item.dart';
import '../services/api_service.dart';
import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';
import 'instance_dropdown.dart';
import 'pulsing_dot.dart';

class CurrentInstanceBadge extends StatelessWidget {
  final VoidCallback? onInstanceChanged;

  const CurrentInstanceBadge({
    super.key,
    this.onInstanceChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = isDark ? AppColors.primaryDark : AppColors.primaryLight;
    final hairline = isDark ? AppColors.dividerHairlineDark : AppColors.dividerHairlineLight;
    final l10n = context.l10n;

    return ValueListenableBuilder<String?>(
      valueListenable: ApiService.instance.activeInstanceNotifier,
      builder: (context, activeId, _) {
        final currentId = activeId ?? ApiService.instance.currentInstanceId;
        if (currentId == null || currentId.isEmpty) {
          return const SizedBox.shrink();
        }

        return FutureBuilder<List<InstanceItem>>(
          future: ApiService.instance.getInstances(),
          builder: (context, snapshot) {
            final list = snapshot.data ?? [];
            final current = list.where((i) => i.id == currentId).firstOrNull;
            final name = current?.name.isNotEmpty == true ? current!.name : currentId;
            final port = current?.port ?? 27015;
            final isRunning = current?.isRunning == true;
            final isStarting = current?.isStarting == true;
            final isSdr = (current?.networkMode ?? 'sdr') == 'sdr';
            final gameIdStr = (isSdr && current?.gameId.isNotEmpty == true) ? '\nGame ID: ${current!.gameId}' : '';
            final tooltipMsg = '${l10n.currentManaging}: $name\n${l10n.networkMode}: ${isSdr ? "Steam SDR" : l10n.direct}\n${l10n.specPort}: $port$gameIdStr\n${l10n.switchInstance}';

            Widget badgeWidget = Builder(
              builder: (badgeContext) {
                return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => showInstanceDropdownFromContext(
                        badgeContext,
                        onInstanceChanged: onInstanceChanged,
                      ),
                      borderRadius: BorderRadius.circular(AppCorner.full),
                      child: Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: ShapeDecoration(
                          color: SurfaceLevel.inset.colorOf(context),
                          shape: StadiumBorder(
                            side: BorderSide(
                              color: isRunning
                                  ? primaryColor.withValues(alpha: 0.35)
                                  : hairline,
                              width: 0.8,
                            ),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            PulsingDot(
                              color: isRunning
                                  ? (isDark ? AppColors.stateSuccessDark : AppColors.stateSuccessLight)
                                  : (isStarting
                                      ? (isDark ? AppColors.stateWarningDark : AppColors.stateWarningLight)
                                      : Colors.grey),
                              isPulsing: isRunning || isStarting,
                              size: 7,
                            ),
                            const SizedBox(width: 7),
                            Icon(Icons.dns_rounded, size: 14, color: primaryColor),
                            const SizedBox(width: 5),
                            if (MediaQuery.sizeOf(context).width >= 520) ...[
                              Text(
                                '${l10n.currentInstanceLabel}: ',
                                style: AppTextStyle.caption2.of(
                                  context,
                                  color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                                ),
                              ),
                            ],
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: MediaQuery.sizeOf(context).width < 520 ? 90 : 130,
                              ),
                              child: Text(
                                name,
                                style: AppTextStyle.caption1.of(context, emphasized: true),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            // SDR / Direct Mode Tag
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: isSdr
                                    ? (isDark ? const Color(0xFF143823) : const Color(0xFFE6F4EA))
                                    : (isDark ? const Color(0xFF2B2538) : const Color(0xFFF1EBFB)),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: isSdr
                                      ? (isDark ? const Color(0xFF34A853).withValues(alpha: 0.6) : const Color(0xFF34A853).withValues(alpha: 0.4))
                                      : (isDark ? primaryColor.withValues(alpha: 0.5) : primaryColor.withValues(alpha: 0.3)),
                                  width: 0.6,
                                ),
                              ),
                              child: Text(
                                isSdr ? 'SDR' : l10n.direct,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.3,
                                  color: isSdr
                                      ? (isDark ? const Color(0xFF81C995) : const Color(0xFF137333))
                                      : (isDark ? AppColors.primaryDark : AppColors.primaryLight),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '($port)',
                              style: AppTextStyle.caption2.of(
                                context,
                                color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                                tabular: true,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 16,
                              color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );

            // On mobile / touch devices (< 720dp), do not show hover tooltip popup
            if (MediaQuery.sizeOf(context).width < 720) {
              return badgeWidget;
            }

            return Tooltip(
              message: tooltipMsg,
              waitDuration: const Duration(milliseconds: 500),
              child: badgeWidget,
            );
          },
        );
      },
    );
  }
}
