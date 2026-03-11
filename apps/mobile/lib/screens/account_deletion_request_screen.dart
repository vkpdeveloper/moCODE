import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/providers.dart';
import '../theme/app_theme.dart';

class AccountDeletionRequestScreen extends ConsumerStatefulWidget {
  const AccountDeletionRequestScreen({super.key});

  @override
  ConsumerState<AccountDeletionRequestScreen> createState() =>
      _AccountDeletionRequestScreenState();
}

class _AccountDeletionRequestScreenState
    extends ConsumerState<AccountDeletionRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController();
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final email = _emailController.text.trim();
    if (email.isEmpty) return;

    setState(() => _isSubmitting = true);
    try {
      final service = ref.read(accountServiceProvider);
      await service.requestAccountDeletion(email: email);
      if (!mounted) return;
      _emailController.clear();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Request submitted.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to submit: $error')));
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Enter your email address.';
    const pattern = r'^[^@\s]+@[^@\s]+\.[^@\s]+$';
    final regex = RegExp(pattern);
    if (!regex.hasMatch(email)) return 'Enter a valid email address.';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final canPop = context.canPop();
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: canPop,
        leading: canPop
            ? IconButton(
                icon: const Icon(Icons.arrow_back, size: 20),
                onPressed: () => context.pop(),
              )
            : null,
        title: const Text(
          'ACCOUNT DELETION',
          style: TextStyle(fontSize: 14, letterSpacing: 2),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Request account deletion',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          const Text(
            'Enter the email address tied to your account. We will store the request and follow up shortly.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              border: Border.all(color: AppTheme.border),
            ),
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Email address',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textCapitalization: TextCapitalization.none,
                    autocorrect: false,
                    enableSuggestions: false,
                    autofillHints: const [AutofillHints.email],
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 13,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'name@example.com',
                      isDense: true,
                    ),
                    validator: _validateEmail,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submit,
                      child: _isSubmitting
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text(
                              'SUBMIT REQUEST',
                              style: TextStyle(fontSize: 12, letterSpacing: 1),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
