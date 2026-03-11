import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../providers/providers.dart';

class PaymentCheckoutScreen extends ConsumerStatefulWidget {
  const PaymentCheckoutScreen({super.key});

  @override
  ConsumerState<PaymentCheckoutScreen> createState() =>
      _PaymentCheckoutScreenState();
}

class _PaymentCheckoutScreenState extends ConsumerState<PaymentCheckoutScreen> {
  WebViewController? _controller;
  bool _loading = true;
  String? _error;
  bool _handledReturn = false;

  @override
  void initState() {
    super.initState();
    _loadCheckout();
  }

  Future<void> _loadCheckout() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = ref.read(firebaseUserProvider);
      if (user == null) {
        throw Exception('Sign in with Google first');
      }

      final idToken = await user.getIdToken();
      if (idToken == null || idToken.isEmpty) {
        throw Exception('Unable to fetch Firebase ID token');
      }

      final checkoutUrl = await ref
          .read(accountServiceProvider)
          .createCheckoutSession(idToken);

      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (request) {
              if (_isPaymentCompletionUrl(request.url)) {
                _onPaymentReturn(Uri.parse(request.url));
                return NavigationDecision.prevent;
              }
              return NavigationDecision.navigate;
            },
          ),
        )
        ..loadRequest(Uri.parse(checkoutUrl));

      if (!mounted) return;
      setState(() {
        _controller = controller;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  bool _isPaymentCompletionUrl(String url) {
    final current = Uri.parse(url);
    return current.queryParameters.containsKey('payment_id') &&
        current.queryParameters.containsKey('status');
  }

  void _onPaymentReturn(Uri uri) {
    if (_handledReturn) return;
    _handledReturn = true;

    ref.invalidate(idTokenProvider);
    ref.invalidate(accountProfileProvider);
    ref.invalidate(billingStatusProvider);

    if (!mounted) return;

    final status = uri.queryParameters['status'];
    final isSuccess = status == null || status.isEmpty || status == 'succeeded';
    if (!isSuccess) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Payment status: $status')));
    }

    context.go('/settings', extra: {'refreshPayment': true});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Secure Setup')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Could not open secure setup',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _loadCheckout,
                      child: const Text('TRY AGAIN'),
                    ),
                  ],
                ),
              ),
            )
          : WebViewWidget(controller: _controller!),
    );
  }
}
