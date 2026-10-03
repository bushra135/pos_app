import 'package:flutter/material.dart';

/// Shared sky blue and turquoise palette for all screens.
abstract final class AppColors {
  static const Color primary = Color(0xFF087F9C);
  static const Color primaryDark = Color(0xFF075C78);
  static const Color accent = primary;
  static const Color onBrand = Colors.white;
  static const Color background = Color(0xFFE8F3F7);
  static const Color surface = Colors.white;
  static const Color text = Color(0xFF153652);
  static const Color muted = Color(0xFF58748B);
  static const Color border = Color(0xFFC4DCE5);
  static const Color soft = Color(0xFFDDEFF4);
  static const Color successSoft = Color(0xFFEAF6F0);
  static const Color warningSoft = Color(0xFFFFF5E8);
  static const Color dangerSoft = Color(0xFFFFEEF0);
  static const Color accentSoft = soft;
  static const Color success = Color(0xFF16845E);
  static const Color warning = Color(0xFFAD690F);
  static const Color danger = Color(0xFFC83D52);

  // Headers and action buttons use the exact same gradient and foreground.
  static const LinearGradient brandGradient = LinearGradient(
    colors: [Color(0xFF007FA9), primary, Color(0xFF00838F)],
    stops: [0, 0.45, 1],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
