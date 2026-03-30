import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../extensions/async_value_extensions.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../utils/app_snackbar.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TextEditingController _hostController;
  late TextEditingController _portController;
  bool _authLoading = false;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _hostController = TextEditingController(text: settings.serverHost);
    _portController = TextEditingController(
      text: settings.serverPort.toString(),
    );
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final healthAsync = ref.watch(healthProvider);
    final defaultModel = ref.watch(defaultModelProvider);
    final authState = ref.watch(authStateProvider);
    final accessStatus = ref.watch(accessGateStatusProvider);
    final firebaseUser = authState.valueOrNull;

    final canAccess = accessStatus == AccessGateStatus.granted;
    final needsAccess = !canAccess;
    final canShowBack = canAccess && context.canPop();

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: canShowBack,
        leading: canShowBack
            ? IconButton(
                icon: const Icon(Icons.arrow_back, size: 20),
                onPressed: () => context.pop(),
              )
            : null,
        title: const Text(
          'SETTINGS',
          style: TextStyle(fontSize: 14, letterSpacing: 2),
        ),
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _sectionHeader('SERVER CONNECTION'),
              const SizedBox(height: 8),
              Opacity(
                opacity: canAccess ? 1 : 0.45,
                child: AbsorbPointer(
                  absorbing: !canAccess,
                  child: Column(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          border: Border.all(color: AppTheme.border),
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Host',
                              style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _hostController,
                              style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 13,
                              ),
                              decoration: const InputDecoration(
                                hintText: 'localhost',
                                isDense: true,
                              ),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'Port',
                              style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _portController,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 13,
                              ),
                              decoration: const InputDecoration(
                                hintText: '3000',
                                isDense: true,
                              ),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _saveSettings,
                                child: const Text(
                                  'SAVE & CONNECT',
                                  style: TextStyle(
                                    fontSize: 12,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          border: Border.all(color: AppTheme.border),
                        ),
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            const Text(
                              'Current URL',
                              style: TextStyle(
                                color: AppTheme.textTertiary,
                                fontSize: 11,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              settings.serverUrl,
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),
              _sectionHeader('TERMINAL'),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  border: Border.all(color: AppTheme.border),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Nerd Fonts',
                            style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Show icons and glyphs in terminal',
                            style: TextStyle(
                              color: AppTheme.textTertiary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: settings.useNerdFont,
                      activeColor: AppTheme.accent,
                      onChanged: (value) {
                        ref
                            .read(settingsProvider.notifier)
                            .updateNerdFont(value);
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              _sectionHeader('STATUS'),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  border: Border.all(color: AppTheme.border),
                ),
                padding: const EdgeInsets.all(16),
                child: healthAsync.when(
                  data: (health) => Column(
                    children: [
                      _statusRow(
                        'Server',
                        health.healthy ? 'Online' : 'Offline',
                        health.healthy,
                      ),
                      const Divider(height: 20),
                      _statusRow('Version', health.version ?? 'Unknown', null),
                    ],
                  ),
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(
                        color: AppTheme.accent,
                        strokeWidth: 2,
                      ),
                    ),
                  ),
                  error: (e, _) => _statusRow('Server', 'Offline', false),
                ),
              ),

              const SizedBox(height: 24),
              _sectionHeader('ACCOUNT'),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  border: Border.all(
                    color: needsAccess ? AppTheme.accent : AppTheme.border,
                    width: needsAccess ? 1.4 : 1,
                  ),
                  boxShadow: needsAccess
                      ? [
                          BoxShadow(
                            color: AppTheme.accent.withValues(alpha: 0.12),
                            blurRadius: 18,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  children: [
                    if (needsAccess)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                        decoration: BoxDecoration(
                          color: AppTheme.accent.withValues(alpha: 0.12),
                          border: Border(
                            bottom: BorderSide(color: AppTheme.border),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.lock_outline,
                              size: 16,
                              color: AppTheme.accent,
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Sign in to unlock access',
                                style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ListTile(
                      leading: Icon(
                        firebaseUser == null ? Icons.login : Icons.verified,
                        color: firebaseUser != null
                            ? AppTheme.success
                            : AppTheme.textSecondary,
                        size: 20,
                      ),
                      title: Text(
                        firebaseUser == null
                            ? 'Sign in with Google'
                            : (firebaseUser.displayName ??
                                  firebaseUser.email ??
                                  'Signed in'),
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: firebaseUser == null
                          ? const Text(
                              'Sign in to get started',
                              style: TextStyle(
                                color: AppTheme.textTertiary,
                                fontSize: 11,
                              ),
                            )
                          : const Text(
                              'You are all set. Full access is active.',
                              style: TextStyle(
                                color: AppTheme.success,
                                fontSize: 11,
                              ),
                            ),
                      trailing: _authLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(
                              Icons.chevron_right,
                              color: AppTheme.textTertiary,
                              size: 18,
                            ),
                      onTap: _authLoading
                          ? null
                          : () {
                              if (firebaseUser == null) {
                                _signInWithGoogle();
                                return;
                              }
                              _signOut();
                            },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              _sectionHeader('ACTIONS'),
              const SizedBox(height: 8),
              Opacity(
                opacity: canAccess ? 1 : 0.45,
                child: AbsorbPointer(
                  absorbing: !canAccess,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(
                            Icons.refresh,
                            color: AppTheme.textSecondary,
                            size: 20,
                          ),
                          title: const Text(
                            'Refresh All Data',
                            style: TextStyle(fontSize: 13),
                          ),
                          trailing: const Icon(
                            Icons.chevron_right,
                            color: AppTheme.textTertiary,
                            size: 18,
                          ),
                          onTap: () {
                            ref.invalidate(healthProvider);
                            ref.invalidate(projectsProvider);
                            ref.invalidate(sessionsProvider);
                            ref.invalidate(providersListProvider);
                            AppSnackBar.showInfo(context, 'Refreshing...');
                          },
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(
                            Icons.model_training,
                            color: AppTheme.textSecondary,
                            size: 20,
                          ),
                          title: const Text(
                            'Default Model',
                            style: TextStyle(fontSize: 13),
                          ),
                          subtitle: defaultModel != null
                              ? Text(
                                  '${defaultModel['providerID']}/${defaultModel['modelID']}',
                                  style: const TextStyle(
                                    color: AppTheme.textTertiary,
                                    fontSize: 11,
                                  ),
                                )
                              : null,
                          trailing: const Icon(
                            Icons.chevron_right,
                            color: AppTheme.textTertiary,
                            size: 18,
                          ),
                          onTap: () {
                            context.push('/models', extra: {'mode': 'default'});
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),
              _sectionHeader('ABOUT'),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  border: Border.all(color: AppTheme.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'moCODE',
                            style: TextStyle(
                              color: AppTheme.accent,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Connect with your OpenCode server',
                            style: TextStyle(
                              color: AppTheme.textTertiary,
                              fontSize: 11,
                            ),
                          ),
                          SizedBox(height: 12),
                          Text(
                            'BUILD',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Built with ❤️ by Ordinity',
                            style: TextStyle(
                              color: AppTheme.accent,
                              fontSize: 11,
                            ),
                          ),
                          SizedBox(height: 12),
                          Text(
                            'VERSION',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'v1.0.0',
                            style: TextStyle(
                              color: AppTheme.textTertiary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(
                        Icons.code,
                        color: AppTheme.textSecondary,
                        size: 20,
                      ),
                      title: const Text(
                        'View on GitHub',
                        style: TextStyle(fontSize: 13),
                      ),
                      subtitle: const Text(
                        'Open source — free forever',
                        style: TextStyle(
                          color: AppTheme.textTertiary,
                          fontSize: 11,
                        ),
                      ),
                      trailing: const Icon(
                        Icons.open_in_new,
                        color: AppTheme.textTertiary,
                        size: 18,
                      ),
                      onTap: () {
                        launchUrl(
                          Uri.parse(
                            'https://github.com/vkpdeveloper/moCODE',
                          ),
                          mode: LaunchMode.externalApplication,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Text(
        title,
        style: const TextStyle(
          color: AppTheme.textTertiary,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 2,
        ),
      ),
    );
  }

  Widget _statusRow(String label, String value, bool? isGood) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        ),
        const Spacer(),
        if (isGood != null)
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(right: 6),
            color: isGood ? AppTheme.success : AppTheme.error,
          ),
        Text(
          value,
          style: TextStyle(
            color: isGood == null
                ? AppTheme.textPrimary
                : (isGood ? AppTheme.success : AppTheme.error),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  void _saveSettings() {
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 3000;
    ref.read(settingsProvider.notifier).updateServer(host, port);
    ref.read(settingsReloadProvider.future);
    ref.invalidate(healthProvider);
    ref.invalidate(projectsProvider);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Settings saved')));
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _authLoading = true;
    });
    try {
      await ref.read(authServiceProvider).signInWithGoogle();
      _refreshAccountState();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Signed in successfully')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Sign in failed: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _authLoading = false;
        });
      }
    }
  }

  Future<void> _signOut() async {
    setState(() {
      _authLoading = true;
    });
    try {
      await ref.read(authServiceProvider).signOut();
      _refreshAccountState();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Signed out')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Sign out failed: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _authLoading = false;
        });
      }
    }
  }

  void _refreshAccountState() {
    ref.invalidate(idTokenProvider);
    ref.invalidate(accountProfileProvider);
  }
}
