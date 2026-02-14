import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ssh_credentials.dart';
import '../providers/ssh_provider.dart';
import '../theme/app_theme.dart';

class SshConnectionDialog extends ConsumerStatefulWidget {
  final String defaultHost;
  final String workingDirectory;

  const SshConnectionDialog({
    super.key,
    required this.defaultHost,
    required this.workingDirectory,
  });

  @override
  ConsumerState<SshConnectionDialog> createState() => _SshConnectionDialogState();
}

class _SshConnectionDialogState extends ConsumerState<SshConnectionDialog> {
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  bool _rememberIdentity = false;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSavedCredentials();
    });
  }

  Future<void> _loadSavedCredentials() async {
    await ref.read(sshProvider.notifier).loadSavedCredentials();
    final saved = ref.read(sshProvider).credentials;
    if (saved != null) {
      setState(() {
        _usernameController.text = saved.username;
        _passwordController.text = saved.password;
        _rememberIdentity = true;
      });
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final host = widget.defaultHost;
    const port = 22;
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (host.isEmpty || username.isEmpty || password.isEmpty) {
      return;
    }

    final credentials = SshCredentials(
      host: host,
      port: port,
      username: username,
      password: password,
      workingDirectory: widget.workingDirectory,
    );

    final success = await ref.read(sshProvider.notifier).connect(
      credentials,
      remember: _rememberIdentity,
    );

    if (success && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sshState = ref.watch(sshProvider);

    return Dialog(
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
            const Text(
              'SSH Connection',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),
            _buildTextField(
              controller: _usernameController,
              label: 'Username',
              hint: 'root',
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _passwordController,
              label: 'Password',
              hint: '••••••••',
              obscureText: true,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Checkbox(
                  value: _rememberIdentity,
                  onChanged: (value) {
                    setState(() {
                      _rememberIdentity = value ?? false;
                    });
                  },
                  activeColor: AppTheme.accent,
                ),
                const Text(
                  'Remember identity',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            if (sshState.error != null) ...[
              const SizedBox(height: 12),
              Text(
                sshState.error!,
                style: const TextStyle(
                  color: AppTheme.error,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: sshState.isConnecting ? null : _connect,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: Colors.white,
                  ),
                  child: sshState.isConnecting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Connect'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscureText,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 13,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
              color: AppTheme.textTertiary,
              fontSize: 13,
            ),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            filled: true,
            fillColor: AppTheme.background,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: const BorderSide(color: AppTheme.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: const BorderSide(color: AppTheme.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: const BorderSide(color: AppTheme.accent),
            ),
          ),
        ),
      ],
    );
  }
}

Future<bool?> showSshConnectionDialog(
  BuildContext context, {
  required String defaultHost,
  required String workingDirectory,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => SshConnectionDialog(
      defaultHost: defaultHost,
      workingDirectory: workingDirectory,
    ),
  );
}
