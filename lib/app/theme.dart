import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_typography.dart';

/// Central Material component styles, typography, and shared colors.
abstract final class AppTheme {
  // Reuse the same fill as page headers rather than a second button palette.
  static Widget _buttonBackground(
    BuildContext context,
    Set<WidgetState> states,
    Widget? child,
  ) => Opacity(
    opacity: states.contains(WidgetState.disabled) ? 0.5 : 1,
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
      ),
      child: child,
    ),
  );

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
      surface: AppColors.surface,
      primary: AppColors.primaryDark,
      onPrimary: Colors.white,
      primaryContainer: AppColors.soft,
      onPrimaryContainer: AppColors.primaryDark,
      secondary: AppColors.primaryDark,
      onSecondary: Colors.white,
      secondaryContainer: AppColors.accentSoft,
      onSecondaryContainer: AppColors.primaryDark,
      onSurface: AppColors.text,
      outline: AppColors.muted,
      outlineVariant: AppColors.border,
      surfaceTint: Colors.transparent,
      error: AppColors.danger,
    );

    return ThemeData(
      useMaterial3: true,
      fontFamily: AppTypography.family,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.text,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: AppColors.text,
          fontFamily: AppTypography.family,
          fontSize: AppTypography.title,
          fontWeight: FontWeight.w700,
          height: 1.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.background,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        hintStyle: const TextStyle(color: AppColors.muted),
        labelStyle: const TextStyle(color: AppColors.muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
          borderSide: const BorderSide(
            color: AppColors.primaryDark,
            width: 1.6,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onBrand,
          elevation: 0,
          shadowColor: Colors.transparent,
          backgroundBuilder: _buttonBackground,
          minimumSize: const Size(48, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
          ),
          textStyle: const TextStyle(
            fontFamily: AppTypography.family,
            fontSize: AppTypography.button,
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primaryDark,
          side: const BorderSide(color: AppColors.border),
          minimumSize: const Size(48, 48),
          textStyle: const TextStyle(
            fontFamily: AppTypography.family,
            fontSize: AppTypography.button,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
          ),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.primaryDark,
        unselectedItemColor: AppColors.muted,
        selectedLabelStyle: TextStyle(
          fontFamily: AppTypography.family,
          fontWeight: FontWeight.w600,
          fontSize: AppTypography.caption,
        ),
        unselectedLabelStyle: TextStyle(
          fontFamily: AppTypography.family,
          fontWeight: FontWeight.w400,
          fontSize: AppTypography.caption,
        ),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedIconTheme: IconThemeData(size: 24),
        unselectedIconTheme: IconThemeData(size: 22),
      ),
      iconTheme: const IconThemeData(color: AppColors.muted, size: 24),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primaryDark,
          minimumSize: const Size(48, 48),
          textStyle: const TextStyle(
            fontFamily: AppTypography.family,
            fontSize: AppTypography.button,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onBrand,
        elevation: 2,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppSpacing.cardRadius),
          ),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primaryDark,
      ),
      dividerColor: AppColors.border,
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.text,
        contentTextStyle: const TextStyle(
          fontFamily: AppTypography.family,
          color: Colors.white,
          fontSize: AppTypography.body,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        ),
      ),
      textTheme: ThemeData.light().textTheme
          .copyWith(
            headlineSmall: const TextStyle(
              color: AppColors.text,
              fontSize: AppTypography.title,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
            titleLarge: const TextStyle(
              color: AppColors.text,
              fontSize: AppTypography.title,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
            titleMedium: const TextStyle(
              color: AppColors.text,
              fontSize: AppTypography.section,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
            bodyLarge: const TextStyle(
              color: AppColors.text,
              fontSize: AppTypography.body,
              height: 1.5,
            ),
            bodyMedium: const TextStyle(
              color: AppColors.text,
              fontSize: AppTypography.body,
              height: 1.5,
            ),
            bodySmall: const TextStyle(
              color: AppColors.muted,
              fontSize: AppTypography.caption,
              height: 1.5,
            ),
            labelLarge: const TextStyle(
              color: AppColors.text,
              fontSize: AppTypography.label,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          )
          .apply(
            fontFamily: AppTypography.family,
            bodyColor: AppColors.text,
            displayColor: AppColors.text,
          ),
    );
  }
}
