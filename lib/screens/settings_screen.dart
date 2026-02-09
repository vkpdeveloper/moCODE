import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/providers.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TextEditingController _hostController;
  late TextEditingController _portController;
  bool _authLoading = false;
  bool _checkoutLoading = false;

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
    final firebaseUser = authState.valueOrNull;
    final profileAsync = ref.watch(accountProfileProvider);
    final billingAsync = ref.watch(billingStatusProvider);
    final billingData = billingAsync.valueOrNull;
    final oneTimeUnlocked = billingData?['oneTimeUnlocked'] == true;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 20),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'SETTINGS',
          style: TextStyle(fontSize: 14, letterSpacing: 2),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionHeader('SERVER CONNECTION'),
          const SizedBox(height: 8),
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
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
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
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
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
                      style: TextStyle(fontSize: 12, letterSpacing: 1),
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
                  style: TextStyle(color: AppTheme.textTertiary, fontSize: 11),
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
          _sectionHeader('ACCOUNT & BILLING'),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: Icon(
                    firebaseUser == null
                        ? Icons.login
                        : (oneTimeUnlocked
                              ? Icons.verified
                              : Icons.account_circle),
                    color: oneTimeUnlocked
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
                          'Required for one-time unlock',
                          style: TextStyle(
                            color: AppTheme.textTertiary,
                            fontSize: 11,
                          ),
                        )
                      : Text(
                          oneTimeUnlocked
                              ? 'One-time access unlocked'
                              : 'Payment required to unlock access',
                          style: TextStyle(
                            color: oneTimeUnlocked
                                ? AppTheme.success
                                : AppTheme.textTertiary,
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
                if (firebaseUser != null) const Divider(height: 1),
                if (firebaseUser != null)
                  ListTile(
                    leading: const Icon(
                      Icons.payments,
                      color: AppTheme.textSecondary,
                      size: 20,
                    ),
                    title: const Text(
                      'Unlock One-Time Access',
                      style: TextStyle(fontSize: 13),
                    ),
                    subtitle: Text(
                      oneTimeUnlocked
                          ? 'Already unlocked'
                          : 'Open Dodo Payments checkout',
                      style: TextStyle(
                        color: oneTimeUnlocked
                            ? AppTheme.success
                            : AppTheme.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                    trailing: _checkoutLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(
                            Icons.open_in_new,
                            color: AppTheme.textTertiary,
                            size: 18,
                          ),
                    onTap: _checkoutLoading || oneTimeUnlocked
                        ? null
                        : _startCheckout,
                  ),
                if (firebaseUser != null) const Divider(height: 1),
                if (firebaseUser != null)
                  ListTile(
                    leading: const Icon(
                      Icons.sync,
                      color: AppTheme.textSecondary,
                      size: 20,
                    ),
                    title: const Text(
                      'Refresh Account Status',
                      style: TextStyle(fontSize: 13),
                    ),
                    subtitle: Text(
                      _billingSubtitle(
                        billingData,
                        profileAsync.valueOrNull,
                        authState.error,
                        billingAsync.error,
                      ),
                      style: const TextStyle(
                        color: AppTheme.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: AppTheme.textTertiary,
                      size: 18,
                    ),
                    onTap: _refreshAccountState,
                  ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          _sectionHeader('ACTIONS'),
          const SizedBox(height: 8),
          Container(
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
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Refreshing...')),
                    );
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

          const SizedBox(height: 24),
          _sectionHeader('ABOUT'),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              border: Border.all(color: AppTheme.border),
            ),
            padding: const EdgeInsets.all(16),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                  'Connect with your Opencode server',
                  style: TextStyle(color: AppTheme.textTertiary, fontSize: 11),
                ),
                SizedBox(height: 12),
                Text(
                  'REPOSITORY',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                SizedBox(height: 2),
                SelectableText(
                  'https://github.com/vkpdeveloper/moCODE',
                  style: TextStyle(color: AppTheme.accent, fontSize: 11),
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
                  style: TextStyle(color: AppTheme.textTertiary, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _billingSubtitle(
    Map<String, dynamic>? billing,
    Map<String, dynamic>? profile,
    Object? authError,
    Object? billingError,
  ) {
    if (authError != null || billingError != null) {
      return 'Unable to fetch account status';
    }
    if (billing == null) {
      return 'Sign in to load account details';
    }
    if (billing['oneTimeUnlocked'] == true) {
      final paidAt = billing['paidAt']?.toString();
      if (paidAt == null || paidAt.isEmpty) {
        return 'Unlocked via one-time payment';
      }
      return 'Unlocked on $paidAt';
    }
    final email = profile?['user']?['email']?.toString();
    if (email != null && email.isNotEmpty) {
      return 'Logged in as $email';
    }
    return 'Awaiting one-time payment';
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

  Future<void> _startCheckout() async {
    final user = ref.read(firebaseUserProvider);
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in with Google first')),
      );
      return;
    }

    setState(() {
      _checkoutLoading = true;
    });

    try {
      final idToken = await user.getIdToken();
      if (idToken == null || idToken.isEmpty) {
        throw Exception('Unable to fetch Firebase ID token');
      }
      final checkoutUrl = await ref
          .read(accountServiceProvider)
          .createCheckoutSession(idToken);

      await launchUrl(
        Uri.parse(checkoutUrl),
        mode: LaunchMode.externalApplication,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Checkout opened. Complete payment and refresh status.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Checkout failed: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _checkoutLoading = false;
        });
      }
    }
  }

  void _refreshAccountState() {
    ref.invalidate(idTokenProvider);
    ref.invalidate(accountProfileProvider);
    ref.invalidate(billingStatusProvider);
  }
}
