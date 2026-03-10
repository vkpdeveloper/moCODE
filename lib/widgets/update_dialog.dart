import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../theme/app_theme.dart';

class UpdateDialog extends ConsumerStatefulWidget {
  const UpdateDialog({super.key});

  @override
  ConsumerState<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends ConsumerState<UpdateDialog> {
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _startImmediateUpdate();
  }

  Future<void> _startImmediateUpdate() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    final updateService = ref.read(inAppUpdateServiceProvider);
    await updateService.performImmediateUpdate();
    if (mounted) {
      setState(() {
        _isLoading = false;
        _errorMessage = updateService.errorMessage;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: AppTheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: AppTheme.border),
        ),
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.system_update, color: AppTheme.accent, size: 28),
                  SizedBox(width: 12),
                  Text(
                    'Update Required',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'A new version of moCODE is available and required to continue. Please update to the latest version.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 20),
              if (_isLoading)
                Column(
                  children: [
                    LinearProgressIndicator(
                      value: null,
                      backgroundColor: AppTheme.background,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppTheme.accent,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Starting update...',
                      style: TextStyle(
                        color: AppTheme.textTertiary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                )
              else
                Text(
                  _errorMessage == null
                      ? 'The update will start automatically. If not, please try again.'
                      : 'Could not start in-app update. Use Retry or open the Play Store.',
                  style: const TextStyle(
                    color: AppTheme.textTertiary,
                    fontSize: 12,
                  ),
                ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!_isLoading)
                    TextButton(
                      onPressed: () async {
                        final updateService = ref.read(
                          inAppUpdateServiceProvider,
                        );
                        await updateService.openPlayStoreListing();
                      },
                      child: const Text(
                        'Open Play Store',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                    ),
                  if (!_isLoading)
                    TextButton(
                      onPressed: _startImmediateUpdate,
                      child: const Text(
                        'Retry',
                        style: TextStyle(color: AppTheme.accent),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class UpdateOverlay extends ConsumerWidget {
  final Widget child;

  const UpdateOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isUpdateAvailable = ref.watch(updateAvailableProvider);

    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        child,
        if (isUpdateAvailable)
          Container(
            color: Colors.black54,
            child: const Center(child: UpdateDialog()),
          ),
      ],
    );
  }
}
