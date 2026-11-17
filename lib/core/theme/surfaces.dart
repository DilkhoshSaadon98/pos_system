import 'package:flutter/material.dart';

import 'app_colors.dart';

/// The handful of colours a screen needs that a [ColorScheme] does not name.
///
/// Widgets ask for `theme.surfaces.hairline` rather than reaching for a
/// constant, so the same table looks right on the light back office and on the
/// dark till without a single `if (isDark)` in the widget itself.
class Surfaces {
  const Surfaces({
    required this.raised,
    required this.hairline,
    required this.muted,
    required this.page,
    required this.overlay,
  });

  /// A panel that should sit a step above the card it lives in — table
  /// headers, totals strips, the keypad.
  final Color raised;

  /// Dividers and card borders: the thinnest visible line, nothing more.
  final Color hairline;

  /// Secondary text — labels, hints, timestamps.
  final Color muted;

  /// The scaffold background.
  final Color page;

  /// A wash laid over content: a selected row, a hovered tile, a scrim.
  final Color overlay;
}

extension AppThemeSurfaces on ThemeData {
  bool get isDark => brightness == Brightness.dark;

  Surfaces get surfaces => isDark
      ? Surfaces(
          raised: AppColors.darkSurfaceAlt,
          hairline: AppColors.darkBorder,
          muted: AppColors.darkTextMuted,
          page: AppColors.darkBackground,
          overlay: Colors.white.withValues(alpha: 0.05),
        )
      : Surfaces(
          raised: AppColors.lightSurfaceAlt,
          hairline: AppColors.lightBorder,
          muted: AppColors.lightTextMuted,
          page: AppColors.lightBackground,
          overlay: Colors.black.withValues(alpha: 0.035),
        );

  /// Shorthands kept because they read better inside a long widget tree.
  Color get mutedText => surfaces.muted;
  Color get surfaceAlt => surfaces.raised;
  Color get borderColor => surfaces.hairline;

  /// Figures on an invoice line up only if they are drawn in a face whose
  /// digits are all the same width. This is that face, at whatever size the
  /// caller was already using.
  TextStyle get tabular => const TextStyle(
        fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
      );
}
