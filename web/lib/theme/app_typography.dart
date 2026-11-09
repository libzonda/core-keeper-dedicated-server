import 'package:flutter/material.dart';

/// 13-Level Dynamic Type Scale
/// Follows the Two-Weight Rule (Regular w400 vs Emphasized w600/w700)
/// and supports tabular numerics (FontFeature.tabularFigures()) for jitter-free data display.
enum AppTextStyle {
  display(40, 44, weight: FontWeight.w700, emphasizedWeight: FontWeight.w700),
  largeTitle(34, 41, weight: FontWeight.w700, emphasizedWeight: FontWeight.w700),
  title1(28, 34, weight: FontWeight.w700, emphasizedWeight: FontWeight.w700),
  pageTitle(24, 30, weight: FontWeight.w600, emphasizedWeight: FontWeight.w700),
  title2(22, 28, weight: FontWeight.w700, emphasizedWeight: FontWeight.w700),
  title3(20, 25, weight: FontWeight.w400, emphasizedWeight: FontWeight.w600),
  headline(17, 22, weight: FontWeight.w600, emphasizedWeight: FontWeight.w700),
  body(17, 22, weight: FontWeight.w400, emphasizedWeight: FontWeight.w600),
  callout(16, 21, weight: FontWeight.w400, emphasizedWeight: FontWeight.w600),
  subheadline(15, 20, weight: FontWeight.w400, emphasizedWeight: FontWeight.w600),
  footnote(13, 18, weight: FontWeight.w400, emphasizedWeight: FontWeight.w600),
  caption1(12, 16, weight: FontWeight.w400, emphasizedWeight: FontWeight.w600),
  caption2(11, 13, weight: FontWeight.w400, emphasizedWeight: FontWeight.w600);

  const AppTextStyle(
    this.size,
    this.leading, {
    this.weight = FontWeight.w400,
    this.emphasizedWeight = FontWeight.w600,
  });

  final double size;
  final double leading;
  final FontWeight weight;
  final FontWeight emphasizedWeight;

  TextStyle of(
    BuildContext context, {
    bool emphasized = false,
    Color? color,
    bool tabular = false,
  }) {
    return TextStyle(
      fontSize: size,
      height: leading / size,
      fontWeight: emphasized ? emphasizedWeight : weight,
      color: color,
      fontFamily: 'Inter',
      letterSpacing: size >= 20 ? -0.3 : 0.0,
      fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
    );
  }
}

/// 8dp Base Grid Spacing Tokens
abstract final class AppSpacing {
  static const double xs = 4.0;    // Icon & trailing text, switch inner inset, tag padding
  static const double sm = 8.0;    // Compact list gap, button group gap, card stack gap
  static const double md = 12.0;   // Form element horizontal gap, compact card padding
  static const double lg = 16.0;   // Standard card padding, list margin
  static const double xl = 20.0;   // Dialog button spacing
  static const double xxl = 24.0;  // Section vertical spacing, dialog outer margin
  static const double xxxl = 32.0; // Dashboard primary section drop
}
