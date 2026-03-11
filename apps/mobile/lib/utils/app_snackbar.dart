import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

enum SnackBarType { info, success, error, warning }

class AppSnackBar {
  static void show(
    BuildContext context, {
    required String message,
    SnackBarType type = SnackBarType.info,
    Duration? duration,
    VoidCallback? onDismiss,
    bool dismissible = true,
  }) {
    final snackBar = SnackBar(
      content: Text(
        message,
        style: const TextStyle(color: AppTheme.textPrimary),
      ),
      backgroundColor: AppTheme.surfaceVariant,
      duration: duration ?? const Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: const RoundedRectangleBorder(),
      dismissDirection: dismissible
          ? DismissDirection.horizontal
          : DismissDirection.none,
    );

    ScaffoldMessenger.of(context).showSnackBar(snackBar).closed.then((reason) {
      if (onDismiss != null) {
        onDismiss();
      }
    });
  }

  static void showLoading(
    BuildContext context, {
    required String message,
    Duration? duration,
  }) {
    final snackBar = SnackBar(
      content: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(width: 12),
          Text(message, style: const TextStyle(color: AppTheme.textPrimary)),
        ],
      ),
      backgroundColor: AppTheme.surfaceVariant,
      duration: duration ?? const Duration(seconds: 10),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: const RoundedRectangleBorder(),
      dismissDirection: DismissDirection.none,
    );
    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }

  static void showInfo(
    BuildContext context,
    String message, {
    Duration? duration,
    VoidCallback? onDismiss,
  }) => show(
    context,
    message: message,
    type: SnackBarType.info,
    duration: duration,
    onDismiss: onDismiss,
  );

  static void showSuccess(
    BuildContext context,
    String message, {
    Duration? duration,
    VoidCallback? onDismiss,
  }) => show(
    context,
    message: message,
    type: SnackBarType.success,
    duration: duration,
    onDismiss: onDismiss,
  );

  static void showError(
    BuildContext context,
    String message, {
    Duration? duration,
    VoidCallback? onDismiss,
  }) => show(
    context,
    message: message,
    type: SnackBarType.error,
    duration: duration,
    onDismiss: onDismiss,
  );

  static void showWarning(
    BuildContext context,
    String message, {
    Duration? duration,
    VoidCallback? onDismiss,
  }) => show(
    context,
    message: message,
    type: SnackBarType.warning,
    duration: duration,
    onDismiss: onDismiss,
  );

  static void dismiss(BuildContext context) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
  }
}
