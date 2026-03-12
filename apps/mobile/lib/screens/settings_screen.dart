import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../extensions/async_value_extensions.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../utils/app_snackbar.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  final bool refreshPaymentOnOpen;

  const SettingsScreen({super.key, this.refreshPaymentOnOpen = false});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _authLoading = false;
  bool _checkoutLoading = false;
  bool _paymentRefreshLoading = false;
  bool _checkedRefreshOnOpen = false;

  @override
  Widget build(BuildContext context) {
    if (!_checkedRefreshOnOpen && widget.refreshPaymentOnOpen) {
      _checkedRefreshOnOpen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _refreshPaymentStateWithLoader();
      });
    }

    final settings = ref.watch(settingsProvider);
    final healthAsync = ref.watch(healthProvider);
    final selectedAgent = ref.watch(selectedAgentProvider);
    final defaultModel = ref.watch(defaultModelProvider);
    final authState = ref.watch(authStateProvider);
    final accessStatus = ref.watch(accessGateStatusProvider);
    final firebaseUser = authState.valueOrNull;
    final profileAsync = ref.watch(accountProfileProvider);
    final billingAsync = ref.watch(billingStatusProvider);
    final billingData = billingAsync.valueOrNull;
    final oneTimeUnlocked = billingData?['oneTimeUnlocked'] == true;

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
              _sectionHeader('DEVICE CONNECTION'),
              const SizedBox(height: 8),
              Column(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      border: Border.all(color: AppTheme.border),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: AppTheme.background,
                                border: Border.all(color: AppTheme.border),
                              ),
                              child: const Icon(
                                Icons.computer_outlined,
                                color: AppTheme.accent,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    settings.connectedDeviceName ??
                                        'No device selected',
                                    style: const TextStyle(
                                      color: AppTheme.textPrimary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    settings.hasSelectedDevice
                                        ? '${settings.serverHost}:${settings.serverPort}'
                                        : 'Open the device picker to select a local machine.',
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
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.background,
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: const Text(
                            'To switch devices, schedule a reset here and restart the app. Your previous pairings stay saved.',
                            style: TextStyle(
                              color: AppTheme.textTertiary,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _scheduleDeviceChange,
                            child: const Text(
                              'CHANGE DEVICE ON NEXT LAUNCH',
                              style: TextStyle(fontSize: 12, letterSpacing: 1),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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
                      activeThumbColor: AppTheme.accent,
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
                        'CLI',
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
                  error: (e, _) => _statusRow('CLI', 'Offline', false),
                ),
              ),

              const SizedBox(height: 24),
              _sectionHeader('ACCOUNT & BILLING'),
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
                                'Sign in and complete setup to unlock access',
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
                              'Sign in to continue setup',
                              style: TextStyle(
                                color: AppTheme.textTertiary,
                                fontSize: 11,
                              ),
                            )
                          : Text(
                              oneTimeUnlocked
                                  ? 'You are all set. Full access is active.'
                                  : 'Complete setup to unlock full access',
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
                          'Complete Setup',
                          style: TextStyle(fontSize: 13),
                        ),
                        subtitle: Text(
                          oneTimeUnlocked
                              ? 'Everything is unlocked'
                              : 'Secure payment, one time only',
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
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
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
                            ref.invalidate(agentsProvider);
                            AppSnackBar.showInfo(context, 'Refreshing...');
                          },
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(
                            Icons.memory_outlined,
                            color: AppTheme.textSecondary,
                            size: 20,
                          ),
                          title: const Text(
                            'Active Agent',
                            style: TextStyle(fontSize: 13),
                          ),
                          subtitle: Text(
                            selectedAgent.agentName ?? 'Choose an agent',
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
                          onTap: settings.hasSelectedDevice
                              ? () {
                                  context.push('/agents');
                                }
                              : null,
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
                                  defaultModel['providerID'] == 'local'
                                      ? 'No model selected'
                                      : defaultModel['modelID']?.toString() ??
                                            '',
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
                      'Connect with your moCODE CLI',
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
                      style: TextStyle(
                        color: AppTheme.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_paymentRefreshLoading)
            Positioned.fill(
              child: Container(
                color: Colors.black54,
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: AppTheme.accent),
                      SizedBox(height: 12),
                      Text(
                        'Confirming your payment... ',
                        style: TextStyle(color: AppTheme.textPrimary),
                      ),
                    ],
                  ),
                ),
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
        return 'Full access is active';
      }
      return 'Access active since $paidAt';
    }
    final email = profile?['user']?['email']?.toString();
    if (email != null && email.isNotEmpty) {
      return 'Logged in as $email';
    }
    return 'Setup incomplete';
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

  Future<void> _scheduleDeviceChange() async {
    await ref.read(settingsProvider.notifier).requestDeviceChangeOnNextLaunch();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Device change saved. Restart the app to choose a different machine.',
        ),
      ),
    );
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
      AppSnackBar.showWarning(context, 'Sign in with Google first');
      return;
    }

    setState(() {
      _checkoutLoading = true;
    });

    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        if (!mounted) return;
        context.push('/payment/checkout');
        AppSnackBar.showInfo(context, 'Opening secure setup...');
        return;
      }

      final idToken = await user.getIdToken();
      if (idToken == null || idToken.isEmpty) {
        throw Exception('Unable to fetch Firebase ID token');
      }
      final checkoutUrl = await ref
          .read(accountServiceProvider)
          .createCheckoutSession(idToken);

      if (!mounted) return;
      await launchUrl(
        Uri.parse(checkoutUrl),
        mode: LaunchMode.externalApplication,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Opening secure setup...')));
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

  Future<void> _refreshPaymentStateWithLoader() async {
    if (_paymentRefreshLoading) return;
    setState(() {
      _paymentRefreshLoading = true;
    });

    var unlocked = false;
    try {
      for (var attempt = 0; attempt < 5; attempt++) {
        _refreshAccountState();
        final billing = await ref.read(billingStatusProvider.future);
        unlocked = billing?['oneTimeUnlocked'] == true;
        if (unlocked) break;
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    } catch (_) {
      // keep silent and show generic status after loader
    } finally {
      if (mounted) {
        setState(() {
          _paymentRefreshLoading = false;
        });
        AppSnackBar.show(
          context,
          message: unlocked
              ? 'Payment confirmed. Full access unlocked.'
              : 'We are still verifying payment. Tap refresh in a moment.',
          type: unlocked ? SnackBarType.success : SnackBarType.info,
        );
      }
    }
  }
}
