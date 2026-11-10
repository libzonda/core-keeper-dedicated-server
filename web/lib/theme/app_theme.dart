import 'package:flutter/material.dart';
import 'app_tokens.dart';

class AppTheme {
  static ThemeData get darkTheme {
    const colorScheme = ColorScheme.dark(
      primary: AppColors.primaryDark,
      onPrimary: Colors.white,
      surface: AppColors.surfacePageDark,
      surfaceContainer: AppColors.surfaceCardDark,
      surfaceContainerHigh: AppColors.surfaceBlockDark,
      surfaceContainerHighest: AppColors.surfaceInsetDark,
      outline: AppColors.dividerHairlineDark,
      error: AppColors.stateErrorDark,
      onError: Colors.black,
    );

    return _buildTheme(
      colorScheme: colorScheme,
      scaffoldBg: AppColors.surfacePageDark,
      cardBg: AppColors.surfaceCardDark,
      blockBg: AppColors.surfaceBlockDark,
      hairline: AppColors.dividerHairlineDark,
      hintColor: AppColors.textSecondaryDark,
    );
  }

  static ThemeData get lightTheme {
    const colorScheme = ColorScheme.light(
      primary: AppColors.primaryLight,
      onPrimary: Colors.white,
      surface: AppColors.surfacePageLight,
      surfaceContainer: AppColors.surfaceCardLight,
      surfaceContainerHigh: AppColors.surfaceBlockLight,
      surfaceContainerHighest: AppColors.surfaceInsetLight,
      outline: AppColors.dividerHairlineLight,
      error: AppColors.stateErrorLight,
      onError: Colors.white,
    );

    return _buildTheme(
      colorScheme: colorScheme,
      scaffoldBg: AppColors.surfacePageLight,
      cardBg: AppColors.surfaceCardLight,
      blockBg: AppColors.surfaceBlockLight,
      hairline: AppColors.dividerHairlineLight,
      hintColor: AppColors.textSecondaryLight,
    );
  }

  static ThemeData _buildTheme({
    required ColorScheme colorScheme,
    required Color scaffoldBg,
    required Color cardBg,
    required Color blockBg,
    required Color hairline,
    required Color hintColor,
  }) {
    return ThemeData(
      useMaterial3: true,
      brightness: colorScheme.brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBg,
      dividerColor: hairline,
      cardColor: cardBg,
      cardTheme: const CardThemeData(
        elevation: 0,
        shape: AppShape.md, // 16dp continuous squircle
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: blockBg,
        border: OutlineInputBorder(
          borderRadius: AppRadius.brSm,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.brSm,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.brSm,
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        hintStyle: TextStyle(color: hintColor, fontSize: 13),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cardBg,
        elevation: 16,
        shape: AppShape.alert, // 34dp Apple squircle
      ),
      dividerTheme: DividerThemeData(
        color: hairline,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: AppShape.sm,
        backgroundColor: colorScheme.brightness == Brightness.dark ? const Color(0xFF23262D) : const Color(0xFF1A1C22),
        contentTextStyle: const TextStyle(
          color: Color(0xFFF4F6FA),
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
