import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/api_error.dart';
import '../theme/app_theme.dart';

/// A widget that displays a user-friendly error view with optional actions.
///
/// This is commonly used to display connection errors on first launch
/// or API errors throughout the app.
class ConnectionErrorView extends StatelessWidget {
  /// The error to display
  final ApiError error;

  /// Callback when retry is tapped
  final VoidCallback? onRetry;

  /// Whether to show the configure button (navigates to settings)
  final bool showConfigureButton;

  /// Custom title override
  final String? title;

  const ConnectionErrorView({
    super.key,
    required this.error,
    this.onRetry,
    this.showConfigureButton = true,
    this.title,
  });

  /// Create from a generic error object
  factory ConnectionErrorView.fromError({
    Key? key,
    required Object error,
    VoidCallback? onRetry,
    bool? showConfigureButton,
    String? title,
  }) {
    final ApiError apiError;
    if (error is ApiError) {
      apiError = error;
    } else {
      apiError = ApiError(
        type: ApiErrorType.unknown,
        message: error.toString(),
      );
    }
    return ConnectionErrorView(
      key: key,
      error: apiError,
      onRetry: onRetry,
      showConfigureButton: showConfigureButton ?? apiError.shouldShowConfigure,
      title: title,
    );
  }

  @override
  Widget build(BuildContext context) {
    final shouldShowConfig = showConfigureButton && error.shouldShowConfigure;
    final displayTitle =
        title ?? (error.isConnectionError ? 'Connection Error' : 'Error');

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Error Icon
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.error.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(_getIcon(), size: 48, color: AppTheme.error),
            ),
            const SizedBox(height: 20),

            // Title
            Text(
              displayTitle,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),

            // Error message
            Text(
              error.message,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),

            // Details (if available)
            if (error.details != null) ...[
              const SizedBox(height: 8),
              Text(
                error.details!,
                style: const TextStyle(
                  color: AppTheme.textTertiary,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ],

            const SizedBox(height: 24),

            // Action buttons
            if (shouldShowConfig) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => context.push('/settings'),
                  icon: const Icon(Icons.settings, size: 18),
                  label: const Text('CONFIGURE SERVER'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            if (onRetry != null)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('RETRY'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  IconData _getIcon() {
    switch (error.type) {
      case ApiErrorType.connection:
        return Icons.cloud_off_outlined;
      case ApiErrorType.timeout:
        return Icons.timer_off_outlined;
      case ApiErrorType.unauthorized:
        return Icons.lock_outline;
      case ApiErrorType.notFound:
        return Icons.search_off_outlined;
      case ApiErrorType.serverError:
        return Icons.error_outline;
      case ApiErrorType.badRequest:
      case ApiErrorType.unknown:
        return Icons.error_outline;
    }
  }
}
