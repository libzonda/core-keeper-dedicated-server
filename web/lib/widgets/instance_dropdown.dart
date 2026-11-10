import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/instance_item.dart';
import '../services/api_service.dart';
import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';
import 'app_toast.dart';
import 'pulsing_dot.dart';

/// Opens the dropdown menu for switching between server instances.
Future<void> showInstanceDropdownFromContext(
  BuildContext context, {
  VoidCallback? onInstanceChanged,
  VoidCallback? onManageInstances,
}) async {
  final box = context.findRenderObject() as RenderBox?;
  if (box == null || !context.mounted) return;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (overlay == null) return;

  final buttonTopLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
  final buttonBottomRight = box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay);
  final buttonRect = Rect.fromPoints(buttonTopLeft, buttonBottomRight);

  final position = RelativeRect.fromRect(
    Rect.fromLTRB(buttonRect.left, buttonRect.bottom + 4, buttonRect.right, buttonRect.bottom + 4),
    Offset.zero & overlay.size,
  );

  await showInstanceDropdown(
    context: context,
    position: position,
    onInstanceChanged: onInstanceChanged,
    onManageInstances: onManageInstances,
  );
}

/// Displays the instance dropdown menu at the given [position].
Future<void> showInstanceDropdown({
  required BuildContext context,
  required RelativeRect position,
  VoidCallback? onInstanceChanged,
  VoidCallback? onManageInstances,
}) async {
  final l10n = context.l10n;
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;
  final primaryColor = isDark ? AppColors.primaryDark : AppColors.primaryLight;
  final hairline = isDark ? AppColors.dividerHairlineDark : AppColors.dividerHairlineLight;
  final currentId = ApiService.instance.currentInstanceId;

  // Fetch real-time instance list
  List<InstanceItem> instances = [];
  try {
    instances = await ApiService.instance.getInstances();
  } catch (_) {}

  if (!context.mounted) return;

  final items = <PopupMenuEntry<String>>[];

  // Header Title
  items.add(
    PopupMenuItem<String>(
      enabled: false,
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Icon(Icons.dns_rounded, size: 15, color: primaryColor),
          const SizedBox(width: 8),
          Text(
            l10n.switchInstanceManage,
            style: AppTextStyle.caption1.of(context, emphasized: true).copyWith(
              color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
            decoration: BoxDecoration(
              color: SurfaceLevel.inset.colorOf(context),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${instances.length}',
              style: AppTextStyle.caption2.of(context, tabular: true),
            ),
          ),
        ],
      ),
    ),
  );

  items.add(
    PopupMenuDivider(
      height: 1,
    ),
  );

  if (instances.isEmpty) {
    items.add(
      PopupMenuItem<String>(
        value: '__manage__',
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            const Icon(Icons.add_circle_outline_rounded, size: 18, color: Colors.grey),
            const SizedBox(width: 8),
            Text(
              l10n.goToCreateInstance,
              style: AppTextStyle.body.of(context),
            ),
          ],
        ),
      ),
    );
  } else {
    for (final inst in instances) {
      final isCurrent = inst.id == currentId;
      final isRunning = inst.isRunning;
      final isStarting = inst.isStarting;
      final isSdr = inst.networkMode == 'sdr';

      items.add(
        PopupMenuItem<String>(
          value: inst.id,
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Row(
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
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      inst.name.isNotEmpty ? inst.name : inst.id,
                      style: AppTextStyle.body.of(context, emphasized: isCurrent).copyWith(
                        color: isCurrent
                            ? primaryColor
                            : (isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight),
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
                          decoration: BoxDecoration(
                            color: isSdr
                                ? (isDark ? const Color(0xFF143823) : const Color(0xFFE6F4EA))
                                : (isDark ? const Color(0xFF2B2538) : const Color(0xFFF1EBFB)),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            isSdr ? 'SDR' : l10n.direct,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: isSdr
                                  ? (isDark ? const Color(0xFF81C995) : const Color(0xFF137333))
                                  : (isDark ? AppColors.primaryDark : AppColors.primaryLight),
                            ),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '${inst.port}',
                          style: AppTextStyle.caption2.of(
                            context,
                            color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                            tabular: true,
                          ),
                        ),
                        if (isRunning) ...[
                          const SizedBox(width: 5),
                          Text(
                            '• ${l10n.instanceRunning}',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: isDark ? AppColors.stateSuccessDark : AppColors.stateSuccessLight,
                            ),
                          ),
                        ] else if (isStarting) ...[
                          const SizedBox(width: 5),
                          Text(
                            '• ${l10n.instanceStarting}',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: isDark ? AppColors.stateWarningDark : AppColors.stateWarningLight,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (isCurrent) ...[
                const SizedBox(width: 8),
                Icon(Icons.check_circle_rounded, size: 18, color: primaryColor),
              ],
            ],
          ),
        ),
      );
    }
  }

  // Footer Divider & All Instances Option
  items.add(
    PopupMenuDivider(
      height: 1,
    ),
  );

  items.add(
    PopupMenuItem<String>(
      value: '__manage__',
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Icon(
            Icons.dashboard_customize_outlined,
            size: 15,
            color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
          ),
          const SizedBox(width: 8),
          Text(
            l10n.navInstances,
            style: AppTextStyle.caption1.of(
              context,
              color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
            ),
          ),
          const Spacer(),
          Icon(
            Icons.arrow_forward_ios_rounded,
            size: 11,
            color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
          ),
        ],
      ),
    ),
  );

  final selected = await showMenu<String>(
    context: context,
    position: position,
    elevation: 12,
    shadowColor: Colors.black.withValues(alpha: isDark ? 0.6 : 0.2),
    color: isDark ? AppColors.surfaceCardDark : AppColors.surfaceCardLight,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppCorner.md),
      side: BorderSide(color: hairline, width: 0.8),
    ),
    constraints: const BoxConstraints(minWidth: 260, maxWidth: 360),
    items: items,
  );

  if (!context.mounted) return;

  if (selected == '__manage__') {
    if (onManageInstances != null) {
      onManageInstances();
    } else {
      ApiService.instance.navigateToTab(1);
    }
  } else if (selected != null && selected.isNotEmpty && selected != currentId) {
    try {
      await ApiService.instance.switchInstance(selected);
      onInstanceChanged?.call();
      final target = instances.where((i) => i.id == selected).firstOrNull;
      final name = target?.name.isNotEmpty == true ? target!.name : selected;
      if (context.mounted) {
        showAppToast(
          context,
          l10n.instanceSwitchedSuccess(name),
          type: ToastType.success,
        );
      }
    } catch (e) {
      if (context.mounted) {
        showAppToast(
          context,
          '${l10n.actionFailed}: $e',
          type: ToastType.error,
        );
      }
    }
  }
}

