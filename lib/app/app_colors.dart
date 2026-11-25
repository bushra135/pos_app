import 'package:flutter/material.dart';

/// The ShopPad "Frost" palette: electric blue for actions, ice blue for selected and
/// highlighted states and deep navy as the ink, on neutral light-grey grounds.
///
/// Token names are kept from earlier palettes so every screen picks up the same look:
/// `primary` and `primaryDark` are the blue used for buttons, links and icons (with
/// [onBrand] text on filled surfaces), and the `hero` tokens style the large summary cards.
/// Gradients are kept to near-flat tonal shifts; colour, not effects, carries the brand.
abstract final class AppColors {
  /// Electric blue: primary buttons, selected states and brand marks (5.3:1 with white).
  static const Color primary = Color(0xFF155DFC);

  /// Deeper electric blue: links, icons and focus on light grounds (6.5:1 on [background]).
  static const Color primaryDark = Color(0xFF0F4BD6);

  /// Soft blue for decorative strokes and secondary highlights.
  static const Color accent = Color(0xFF5C8CFF);

  /// Text and icons placed on [primary] surfaces.
  static const Color onBrand = Color(0xFFFFFFFF);

  /// Deep navy: the ink of the app and the dark brand surface.
  static const Color navy = Color(0xFF142C4E);

  /// Ice blue: selected states and highlights (chips, selected navigation and options).
  static const Color ice = Color(0xFFD9EDFF);

  /// Neutral light grey page ground; blue is kept for actions and selection.
  static const Color background = Color(0xFFF4F5F7);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color text = navy;
  static const Color muted = Color(0xFF5B6472);
  static const Color border = Color(0xFFE1E4E9);

  /// Outline of text fields: 3.5:1 on white, so a field's edge is visible (WCAG 1.4.11).
  static const Color fieldBorder = Color(0xFF838A96);
  static const Color soft = Color(0xFFEEF0F3);
  static const Color successSoft = Color(0xFFE6F5EE);
  static const Color warningSoft = Color(0xFFFFF3E2);
  static const Color dangerSoft = Color(0xFFFDECEE);
  static const Color accentSoft = ice;
  static const Color success = Color(0xFF1F7A55);
  static const Color warning = Color(0xFFA15C07);
  static const Color danger = Color(0xFFB4323F);

  /// Secondary text on filled [primary] surfaces.
  static const Color onBrandMuted = Color(0xFFE6EFFF);

  /// Large summary cards (today's sales, reports, profile): light grey with navy text.
  static const Color hero = Color(0xFFECEEF2);
  static const Color onHero = navy;
  static const Color onHeroMuted = Color(0xFF4B5361);

  /// Dividers and outlines drawn on [hero].
  static const Color heroLine = Color(0xFFD7DBE2);

  /// The summary cards: a barely-there tonal shift between two light greys.
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF3F4F7), Color(0xFFE9ECF0)],
  );

  /// Primary actions that deserve weight (Start sale): electric blue, almost flat.
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1F66FF), primary],
  );
}
