import 'dart:ui';

import 'package:flutter/material.dart';

/// One palette, two moods.
///
/// The admin side is light and calm — long tables, forms, reports, read for
/// minutes at a time. The till is dark and high-contrast, because it is stared
/// at for a whole shift under shop lighting and the numbers have to jump off
/// the screen from an arm's length away. Both come from the same seed colour so
/// the app never looks like two applications stitched together.
class AppColors {
  const AppColors._();

  // Brand
  static const Color brand = Color(0xFF1F6FEB);
  static const Color brandDeep = Color(0x008b8b);
  static const Color accent = Color(0xFF00B894);

  // Semantic
  static const Color ok = Color(0xFF1E9E5A);
  static const Color success = ok;
  static const Color warning = Color(0xFFE0A106);
  static const Color danger = Color(0xFFDC3545);
  static const Color info = Color(0xFF2D9CDB);

  // Light surfaces (admin)
  static const Color lightBackground = Color(0xFFF4F6FA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceAlt = Color(0xFFEFF2F7);
  static const Color lightBorder = Color(0xFFDCE1EA);
  static const Color lightText = Color(0xFF16202E);
  static const Color lightTextMuted = Color(0xFF64748B);

  // Dark surfaces (till)
  static const Color darkBackground = Color(0xFF0D1420);
  static const Color darkSurface = Color(0xFF151E2E);
  static const Color darkSurfaceAlt = Color(0xFF1D293C);
  static const Color darkBorder = Color(0xFF2A3A52);
  static const Color darkText = Color(0xFFE8EEF7);
  static const Color darkTextMuted = Color(0xFF93A3BA);

  /// Category chips and item tiles pick a colour from here by index, so a shop
  /// with no photographs still gets a readable, varied grid.
  static const List<Color> tileTints = <Color>[
    Color(0xFF1F6FEB),
    Color(0xFF00B894),
    Color(0xFFE17055),
    Color(0xFF9B59B6),
    Color(0xFF00A8CC),
    Color(0xFFD9A404),
    Color(0xFF2D9CDB),
    Color(0xFFE84393),
  ];

  static Color tintFor(int seed) => tileTints[seed.abs() % tileTints.length];

  /// A version of [color] that can be read on its own 13–20 % wash.
  ///
  /// A status chip painted in the raw brand green measures about 2.7:1 against
  /// its pale tint — legible to some people, not to others. Darkening it in
  /// light mode and lifting it in dark mode fixes every caller at once, which
  /// matters because half of them (dietary tags, category colours) pass a
  /// colour the shop chose rather than one we picked.
  static Color readableOnTint(Color color, Brightness brightness) {
    final HSLColor hsl = HSLColor.fromColor(color);
    if (brightness == Brightness.dark) {
      return hsl.withLightness(hsl.lightness.clamp(0.62, 0.86)).toColor();
    }
    return hsl.withLightness(hsl.lightness.clamp(0.16, 0.36)).toColor();
  }

  /// The colour a money figure is drawn in: green when it comes in, red when it
  /// goes out, and the surrounding text colour when it is exactly zero.
  static Color? forAmount(int minor) {
    if (minor > 0) return ok;
    if (minor < 0) return danger;
    return null;
  }
}
