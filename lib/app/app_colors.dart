import 'package:flutter/material.dart';

/// Light palette: warm light ground, indigo for actions and soft lavender for key cards.
///
/// Token names are kept from the original palette so every screen picks up the same look:
/// `primary` and `primaryDark` are the indigo used for buttons, links and icons (with
/// [onBrand] text on filled surfaces), and the `hero` tokens style the large summary cards.
abstract final class AppColors {
  /// Indigo for primary buttons, selected states and brand marks on every screen.
  static const Color primary = Color(0xFF4F46E5);

  /// Indigo accent: links, icons, focus rings and highlighted actions.
  static const Color primaryDark = Color(0xFF4F46E5);

  /// Soft indigo for decorative strokes and secondary highlights.
  static const Color accent = Color(0xFF8B85F0);

  /// Text and icons placed on [primary] surfaces.
  static const Color onBrand = Color(0xFFFFFFFF);

  static const Color background = Color(0xFFF6F6F3);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color text = Color(0xFF17181C);
  static const Color muted = Color(0xFF5F6168);
  static const Color border = Color(0xFFE9E9E4);
  static const Color soft = Color(0xFFF0F0EC);
  static const Color successSoft = Color(0xFFE6F5EE);
  static const Color warningSoft = Color(0xFFFFF3E2);
  static const Color dangerSoft = Color(0xFFFDECEE);
  static const Color accentSoft = Color(0xFFECEBFC);
  static const Color success = Color(0xFF1F7A55);
  static const Color warning = Color(0xFFA15C07);
  static const Color danger = Color(0xFFB4323F);

  /// Secondary text on filled [primary] surfaces.
  static const Color onBrandMuted = Color(0xFFDCDAFB);

  /// Large summary cards (today's sales, reports, profile): light lavender with dark text.
  static const Color hero = Color(0xFFECEBFC);
  static const Color onHero = Color(0xFF17181C);
  static const Color onHeroMuted = Color(0xFF55537A);

  /// Dividers and outlines drawn on [hero].
  static const Color heroLine = Color(0xFFD6D3F8);
}
