import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/providers.dart';
import '../theme/app_theme.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _preload();
  }

  Future<void> _preload() async {
    try {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (!mounted) return;
      if (!ref.read(settingsProvider).isLoaded) {
        await ref
            .read(settingsReloadProvider.future)
            .timeout(const Duration(seconds: 5));
        if (!mounted) return;
      }
      final hadError = await ref
          .read(appPreloadProvider.future)
          .timeout(const Duration(seconds: 8), onTimeout: () => true);
      if (!mounted) return;
      setState(() {
        _hasError = hadError;
      });
      context.go('/projects');
    } catch (e) {
      debugPrint('Splash preload failed: $e');
      if (!mounted) return;
      setState(() {
        _hasError = true;
      });
      context.go('/projects');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F0B0B), Color(0xFF1A1515), Color(0xFF0F0B0B)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: AppTheme.accent, width: 1.5),
                ),
                child: const Text(
                  'moCODE',
                  style: TextStyle(
                    color: AppTheme.accent,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 6,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Booting your workspace',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  color: AppTheme.accent,
                  strokeWidth: 2,
                ),
              ),
              if (_hasError) ...[
                const SizedBox(height: 16),
                const Text(
                  'Some services are offline. We will retry in the background.',
                  style: TextStyle(color: AppTheme.textTertiary, fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
