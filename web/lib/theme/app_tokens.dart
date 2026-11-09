import 'package:flutter/material.dart';

/// Color Palette & Surface Tokens
abstract final class AppColors {
  // Primary Brand Accent (Apple HIG Anchored)
  static const Color primaryDark = Color(0xFF4799FF);
  static const Color primaryLight = Color(0xFF007AFF);

  // Surface Tonal Scale (Dark Mode - Tone 6 Baseline)
  static const Color surfacePageDark = Color(0xFF0F0F12);     // Tone 6
  static const Color surfaceCardDark = Color(0xFF1C1C20);     // Tone 15 (+9 step)
  static const Color surfaceBlockDark = Color(0xFF26262B);    // Tone 21 (+6 step)
  static const Color surfaceInsetDark = Color(0xFF323238);    // Tone 27 (+6 step)
  static const Color surfaceChromeDark = Color(0xFF151518);   // Tone 10

  // Surface Tonal Scale (Light Mode - Tone 94 Baseline, near-paper white Tone 98)
  static const Color surfacePageLight = Color(0xFFEDEDF0);    // Tone 94
  static const Color surfaceCardLight = Color(0xFFF9F9FA);    // Tone 98 (Near-paper white, never harsh 100)
  static const Color surfaceBlockLight = Color(0xFFEDEDF0);   // Tone 94 (Soft grey well)
  static const Color surfaceInsetLight = Color(0xFFE2E2E6);   // Tone 90
  static const Color surfaceChromeLight = Color(0xFFE8E8EC);  // Tone 92

  // Text & Hairline Dividers (14% onSurface dark, 12% onSurface light)
  static const Color textPrimaryDark = Color(0xFFF0F0F3);
  static const Color textSecondaryDark = Color(0xFF9EA0A8);
  static const Color dividerHairlineDark = Color(0x24FFFFFF); // 14% onSurface

  static const Color textPrimaryLight = Color(0xFF191C1E);
  static const Color textSecondaryLight = Color(0xFF5E6066);
  static const Color dividerHairlineLight = Color(0x1F000000); // 12% onSurface

  // Semantic Status Colors (Unpolluted by seed color)
  static const Color stateSuccessDark = Color(0xFF6DDC88);
  static const Color stateSuccessBgDark = Color(0xFF113E1E);
  static const Color stateSuccessLight = Color(0xFF1B7C3F);
  static const Color stateSuccessBgLight = Color(0xFFD1F6D9);

  static const Color stateWarningDark = Color(0xFFFFB95B);
  static const Color stateWarningBgDark = Color(0xFF542F00);
  static const Color stateWarningLight = Color(0xFFA15D00);
  static const Color stateWarningBgLight = Color(0xFFFFE8C7);

  static const Color stateErrorDark = Color(0xFFFFB4AB);
  static const Color stateErrorBgDark = Color(0xFF93000A);
  static const Color stateErrorLight = Color(0xFFBA1A1A);
  static const Color stateErrorBgLight = Color(0xFFFFDAD6);

  // Apple systemRed destructive action color
  static const Color stateDestructive = Color(0xFFFF3B30);
  static const Color stateDestructiveDark = Color(0xFFFF453A);
}

/// Four-level surface hierarchy for lightness stepping
enum SurfaceLevel {
  page,
  card,
  block,
  inset;

  SurfaceLevel get next => switch (this) {
    page => card,
    card => block,
    block || inset => inset,
  };

  Color colorOf(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return switch (this) {
      page => isDark ? AppColors.surfacePageDark : AppColors.surfacePageLight,
      card => isDark ? AppColors.surfaceCardDark : AppColors.surfaceCardLight,
      block => isDark ? AppColors.surfaceBlockDark : AppColors.surfaceBlockLight,
      inset => isDark ? AppColors.surfaceInsetDark : AppColors.surfaceInsetLight,
    };
  }

  static SurfaceLevel floatingOf(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? block : card;
  }
}

/// Context-aware surface level scope
class SurfaceScope extends StatelessWidget {
  final SurfaceLevel level;
  final Widget child;

  const SurfaceScope({super.key, required this.level, required this.child});

  static SurfaceLevel of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SurfaceLevelScope>()?.level ??
      SurfaceLevel.page;

  @override
  Widget build(BuildContext context) {
    return _SurfaceLevelScope(level: level, child: child);
  }
}

class _SurfaceLevelScope extends InheritedWidget {
  final SurfaceLevel level;

  const _SurfaceLevelScope({required this.level, required super.child});

  @override
  bool updateShouldNotify(_SurfaceLevelScope oldWidget) => level != oldWidget.level;
}

extension SurfaceContext on BuildContext {
  SurfaceLevel get surfaceLevel => SurfaceScope.of(this);
  SurfaceLevel get raisedSurfaceLevel => surfaceLevel.next;
}

/// Corner Radius Tokens
abstract final class AppCorner {
  static const double none = 0.0;
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;   // Standard Card & Input border
  static const double lg = 20.0;   // Large card & Popup menu
  static const double xl = 24.0;   // Floating panels & Sheets
  static const double xxl = 28.0;  // Large dashboard boards
  static const double alert = 34.0;// Modal Alert Dialog
  static const double full = 1000.0;// Pill buttons, Switches, Segmented Controls, Dock
}

/// Standardized BorderRadius tokens
abstract final class AppRadius {
  static const BorderRadius brNone = BorderRadius.zero;
  static const BorderRadius brXs = BorderRadius.all(Radius.circular(AppCorner.xs));
  static const BorderRadius brSm = BorderRadius.all(Radius.circular(AppCorner.sm));
  static const BorderRadius brMd = BorderRadius.all(Radius.circular(AppCorner.md));
  static const BorderRadius brLg = BorderRadius.all(Radius.circular(AppCorner.lg));
  static const BorderRadius brXl = BorderRadius.all(Radius.circular(AppCorner.xl));
  static const BorderRadius brXxl = BorderRadius.all(Radius.circular(AppCorner.xxl));
  static const BorderRadius brAlert = BorderRadius.all(Radius.circular(AppCorner.alert));
  static const BorderRadius brFull = BorderRadius.all(Radius.circular(AppCorner.full));

  static BorderRadius all(double corner) => BorderRadius.circular(corner);
  static BorderRadius vertical({double top = 0.0, double bottom = 0.0}) =>
      BorderRadius.vertical(top: Radius.circular(top), bottom: Radius.circular(bottom));
}

/// Hardware-accelerated rounded superellipse shapes
abstract final class AppShape {
  static const RoundedRectangleBorder none = RoundedRectangleBorder();
  static const RoundedRectangleBorder xs = RoundedRectangleBorder(borderRadius: AppRadius.brXs);
  static const RoundedRectangleBorder sm = RoundedRectangleBorder(borderRadius: AppRadius.brSm);
  static const RoundedRectangleBorder md = RoundedRectangleBorder(borderRadius: AppRadius.brMd);
  static const RoundedRectangleBorder lg = RoundedRectangleBorder(borderRadius: AppRadius.brLg);
  static const RoundedRectangleBorder xl = RoundedRectangleBorder(borderRadius: AppRadius.brXl);
  static const RoundedRectangleBorder xxl = RoundedRectangleBorder(borderRadius: AppRadius.brXxl);
  static const RoundedRectangleBorder alert = RoundedRectangleBorder(borderRadius: AppRadius.brAlert);
  static const StadiumBorder full = StadiumBorder();
  static const CircleBorder circle = CircleBorder();

  static RoundedRectangleBorder all(double corner) =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(corner));

  static RoundedRectangleBorder vertical({double top = 0.0, double bottom = 0.0}) =>
      RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(top),
          bottom: Radius.circular(bottom),
        ),
      );
}

/// Delay status color mapping
Color delayColorOf(int? delay, bool isDark) {
  if (delay == null || delay <= 0) {
    return isDark ? AppColors.stateErrorDark : AppColors.stateErrorLight;
  }
  if (delay < 600) {
    return isDark ? AppColors.stateSuccessDark : AppColors.stateSuccessLight;
  }
  return isDark ? AppColors.stateWarningDark : AppColors.stateWarningLight;
}
