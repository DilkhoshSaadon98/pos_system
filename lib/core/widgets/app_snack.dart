import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The one-line messages the app talks back with.
///
/// GetX let any file call `Get.snackbar` from anywhere, including from inside a
/// repository — which is how business logic ended up knowing about the user
/// interface. Here a message needs either a [BuildContext] or the app's
/// messenger key, and repositories have neither: they return a `Failure` and
/// the screen decides what to say.
class AppSnack {
  const AppSnack._();

  /// Set on `MaterialApp.scaffoldMessengerKey`. Lets the few places that
  /// legitimately have no context — a background print, the auto-save of a
  /// held cart — still reach the user.
  static final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  static void success(BuildContext? context, String message) =>
      _show(context, message, AppColors.ok, Icons.check_circle_outline);

  static void error(BuildContext? context, String message) => _show(
        context,
        message,
        AppColors.danger,
        Icons.error_outline,
        seconds: 5,
      );

  static void info(BuildContext? context, String message) =>
      _show(context, message, AppColors.info, Icons.info_outline);

  static void warning(BuildContext? context, String message) =>
      _show(context, message, AppColors.warning, Icons.warning_amber_rounded);

  static void _show(
    BuildContext? context,
    String message,
    Color color,
    IconData icon, {
    int seconds = 3,
  }) {
    final ScaffoldMessengerState? messenger = context != null
        ? ScaffoldMessenger.maybeOf(context)
        : messengerKey.currentState;
    if (messenger == null) return;

    messenger
      // A cashier scanning fast can trigger three warnings in a second; only
      // the last one is worth reading.
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          duration: Duration(seconds: seconds),
          behavior: SnackBarBehavior.floating,
          width: null,
          margin: const EdgeInsets.all(16),
          backgroundColor: color,
          content: Row(
            children: <Widget>[
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }
}
