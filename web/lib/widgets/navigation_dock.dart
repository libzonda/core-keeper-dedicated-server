import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../l10n/locale_controller.dart';
import '../theme/app_motion.dart';
import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';
import '../theme/theme_controller.dart';

class DockDestination {
  final IconData icon;
  final String label;

  const DockDestination({required this.icon, required this.label});
}

/// Responsive Floating Mobile / Desktop Navigation Dock
/// Adapts gracefully:
/// - Wide screen (>= 600dp): Full 8-item floating pill dock with spring platter
/// - Narrow screen (< 600dp): 5-item adaptive bottom bar (3 primary + 1 active/quick + 1 'More' sheet)
class NavigationDock extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<DockDestination> destinations;

  static const double _barHeight = 62.0;
  static const double _barPadding = 4.0;
  static const double _edgeMargin = 16.0;

  const NavigationDock({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  void _showMoreSheet(
    BuildContext context,
    AppLocalizations l10n,
    bool isDark,
    Color primaryColor,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (bottomSheetContext) {
        final cardBg = isDark ? AppColors.surfaceCardDark : AppColors.surfaceCardLight;
        final borderCol = isDark ? AppColors.dividerHairlineDark : AppColors.dividerHairlineLight;

        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            decoration: ShapeDecoration(
              color: cardBg,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(24)),
              ),
              shadows: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.18),
                  blurRadius: 32,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 6),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black26,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.apps_rounded, size: 22, color: primaryColor),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          l10n.allFeatures,
                          style: AppTextStyle.headline.of(context, emphasized: true),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(bottomSheetContext).pop(),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1),

                // 2-Column Grid of All Features
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: destinations.length,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 2.5,
                    ),
                    itemBuilder: (context, index) {
                      final dest = destinations[index];
                      final isCurrent = index == selectedIndex;

                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () {
                            Navigator.of(bottomSheetContext).pop();
                            onDestinationSelected(index);
                          },
                          child: Ink(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: isCurrent
                                  ? primaryColor.withValues(alpha: isDark ? 0.22 : 0.12)
                                  : (isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03)),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isCurrent ? primaryColor : borderCol,
                                width: isCurrent ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: isCurrent
                                        ? primaryColor
                                        : (isDark ? Colors.white10 : Colors.black12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    dest.icon,
                                    size: 18,
                                    color: isCurrent
                                        ? Colors.white
                                        : (isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    dest.label,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyle.caption1.of(
                                      context,
                                      emphasized: isCurrent,
                                      color: isCurrent
                                          ? primaryColor
                                          : (isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight),
                                    ),
                                  ),
                                ),
                                if (isCurrent)
                                  Icon(Icons.check_circle_rounded, size: 16, color: primaryColor),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                const Divider(height: 1),

                // Quick Tools (Theme & Language toggle)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      // Theme Switcher Button
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: Icon(
                            isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                            size: 18,
                          ),
                          label: Text(
                            isDark ? l10n.themeLight : l10n.themeDark,
                            style: AppTextStyle.caption1.of(context),
                          ),
                          onPressed: () {
                            ThemeController.instance.toggle();
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Language Switcher Menu
                      Expanded(
                        child: PopupMenuButton<AppLanguage>(
                          tooltip: 'Language',
                          initialValue: LocaleController.instance.value,
                          onSelected: (lang) => LocaleController.instance.setLanguage(lang),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          itemBuilder: (context) => AppLanguage.values.map((lang) {
                            final isSel = lang == LocaleController.instance.value;
                            return PopupMenuItem<AppLanguage>(
                              value: lang,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      lang.label,
                                      style: TextStyle(
                                        fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                                        color: isSel ? primaryColor : null,
                                      ),
                                    ),
                                  ),
                                  if (isSel)
                                    Icon(Icons.check, size: 16, color: primaryColor),
                                ],
                              ),
                            );
                          }).toList(),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: borderCol),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.language_rounded, size: 18),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    LocaleController.instance.value.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyle.caption1.of(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? AppColors.primaryDark : AppColors.primaryLight;
    final count = destinations.length;
    final l10n = context.l10n;

    return SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 600;

          if (isNarrow) {
            // Adaptive 5-Item Bottom Bar:
            // [0: Overview] [1: Instances] [2: Logs] [3: Dynamic Active/Secondary] [4: More]
            final int dynamicIndex = (selectedIndex >= 3 && selectedIndex < count)
                ? selectedIndex
                : 5; // Default to Worlds if in 0, 1, or 2

            final dynamicDest = (dynamicIndex < count)
                ? destinations[dynamicIndex]
                : destinations[0];

            final isDynamicActive = selectedIndex == dynamicIndex;

            return Container(
              height: _barHeight,
              margin: const EdgeInsets.fromLTRB(_edgeMargin, 0, _edgeMargin, 12),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              decoration: ShapeDecoration(
                color: (isDark ? AppColors.surfaceCardDark : AppColors.surfaceCardLight).withValues(alpha: 0.96),
                shape: AppShape.full,
                shadows: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Tab 0: Overview
                  if (count > 0)
                    Expanded(
                      child: _DockItemButton(
                        destination: destinations[0],
                        isSelected: selectedIndex == 0,
                        isDark: isDark,
                        primaryColor: primaryColor,
                        onTap: () => onDestinationSelected(0),
                      ),
                    ),

                  // Tab 1: Instances
                  if (count > 1)
                    Expanded(
                      child: _DockItemButton(
                        destination: destinations[1],
                        isSelected: selectedIndex == 1,
                        isDark: isDark,
                        primaryColor: primaryColor,
                        onTap: () => onDestinationSelected(1),
                      ),
                    ),

                  // Tab 2: Logs
                  if (count > 2)
                    Expanded(
                      child: _DockItemButton(
                        destination: destinations[2],
                        isSelected: selectedIndex == 2,
                        isDark: isDark,
                        primaryColor: primaryColor,
                        onTap: () => onDestinationSelected(2),
                      ),
                    ),

                  // Tab 3: Dynamic Active / Context Tab
                  Expanded(
                    child: _DockItemButton(
                      destination: dynamicDest,
                      isSelected: isDynamicActive,
                      isDark: isDark,
                      primaryColor: primaryColor,
                      onTap: () => onDestinationSelected(dynamicIndex),
                    ),
                  ),

                  // Tab 4: More button
                  Expanded(
                    child: _DockItemButton(
                      destination: DockDestination(
                        icon: Icons.grid_view_rounded,
                        label: l10n.navMore,
                      ),
                      isSelected: false,
                      isDark: isDark,
                      primaryColor: primaryColor,
                      onTap: () => _showMoreSheet(context, l10n, isDark, primaryColor),
                    ),
                  ),
                ],
              ),
            );
          }

          // Wide Screen (>= 600dp): Full 8-item floating pill dock with spring platter
          return Container(
            height: _barHeight,
            margin: const EdgeInsets.fromLTRB(_edgeMargin, 0, _edgeMargin, 12),
            padding: const EdgeInsets.all(_barPadding),
            decoration: ShapeDecoration(
              color: (isDark ? AppColors.surfaceCardDark : AppColors.surfaceCardLight).withValues(alpha: 0.94),
              shape: AppShape.full,
              shadows: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Stack(
              children: [
                // Floating Platter Under Active Tab
                if (selectedIndex >= 0 && selectedIndex < count)
                  AnimatedAlign(
                    duration: const Duration(milliseconds: 320),
                    curve: AppMotion.easeOutCubic,
                    alignment: AlignmentDirectional(
                      count == 1 ? 0.0 : selectedIndex * 2.0 / (count - 1) - 1.0,
                      0.0,
                    ),
                    child: FractionallySizedBox(
                      widthFactor: 1.0 / count,
                      heightFactor: 1.0,
                      child: DecoratedBox(
                        decoration: ShapeDecoration(
                          color: primaryColor.withValues(alpha: isDark ? 0.22 : 0.14),
                          shape: AppShape.full,
                        ),
                      ),
                    ),
                  ),

                // Tab Buttons
                Row(
                  children: [
                    for (int i = 0; i < count; i++)
                      Expanded(
                        child: _DockItemButton(
                          destination: destinations[i],
                          isSelected: i == selectedIndex,
                          isDark: isDark,
                          primaryColor: primaryColor,
                          onTap: () => onDestinationSelected(i),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DockItemButton extends StatelessWidget {
  final DockDestination destination;
  final bool isSelected;
  final bool isDark;
  final Color primaryColor;
  final VoidCallback onTap;

  const _DockItemButton({
    required this.destination,
    required this.isSelected,
    required this.isDark,
    required this.primaryColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = isSelected
        ? primaryColor
        : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          decoration: isSelected
              ? ShapeDecoration(
                  color: primaryColor.withValues(alpha: isDark ? 0.18 : 0.12),
                  shape: AppShape.full,
                )
              : null,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                destination.icon,
                size: 20,
                color: fg,
              ),
              const SizedBox(height: 2),
              Text(
                destination.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppTextStyle.caption2.of(
                  context,
                  emphasized: isSelected,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
