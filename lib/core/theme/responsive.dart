import 'package:flutter/widgets.dart';

/// Screen sizes, named once.
///
/// The same page runs on a 24" till and on a phone in the stockroom. Rather
/// than two copies of every screen — which is how the old project ended up with
/// a `windows/` and a `mobile/` folder that slowly drifted apart — each screen
/// asks which shape it is in and lays itself out accordingly.
enum ScreenSize { mobile, tablet, desktop, wide }

class Responsive {
  const Responsive._();

  static const double mobileMax = 700;
  static const double tabletMax = 1100;
  static const double desktopMax = 1500;

  static ScreenSize of(BuildContext context) =>
      fromWidth(MediaQuery.sizeOf(context).width);

  static ScreenSize fromWidth(double width) {
    if (width < mobileMax) return ScreenSize.mobile;
    if (width < tabletMax) return ScreenSize.tablet;
    if (width < desktopMax) return ScreenSize.desktop;
    return ScreenSize.wide;
  }

  static bool isMobile(BuildContext c) => of(c) == ScreenSize.mobile;
  static bool isTablet(BuildContext c) => of(c) == ScreenSize.tablet;
  static bool isDesktop(BuildContext c) => of(c).index >= ScreenSize.desktop.index;
  static bool isCompact(BuildContext c) => of(c).index <= ScreenSize.tablet.index;

  /// Picks a value per screen size, falling back down the list.
  static T value<T>(
    BuildContext context, {
    required T mobile,
    T? tablet,
    T? desktop,
    T? wide,
  }) {
    switch (of(context)) {
      case ScreenSize.mobile:
        return mobile;
      case ScreenSize.tablet:
        return tablet ?? mobile;
      case ScreenSize.desktop:
        return desktop ?? tablet ?? mobile;
      case ScreenSize.wide:
        return wide ?? desktop ?? tablet ?? mobile;
    }
  }

  /// How many product tiles fit across the till grid.
  static int posGridColumns(double width) {
    if (width < 420) return 2;
    if (width < 700) return 3;
    if (width < 1000) return 4;
    if (width < 1300) return 5;
    if (width < 1700) return 6;
    return 7;
  }
}
