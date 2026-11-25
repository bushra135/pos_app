/// Shared type scale. Cairo is bundled so rendering does not depend on the device.
///
/// Screens use only these sizes; a size that is not here is a design bug.
abstract final class AppTypography {
  static const String family = 'Cairo';

  /// Chart axis ticks only.
  static const double micro = 10;
  static const double caption = 12;
  static const double body = 14;
  static const double label = 14;
  static const double button = 15;
  static const double subtitle = 16;
  static const double section = 18;
  static const double headline = 20;
  static const double metric = 22;
  static const double title = 24;
  static const double display = 28;
  static const double brand = display;

  /// The one large amount on a screen (today's sales).
  static const double hero = 36;
}
