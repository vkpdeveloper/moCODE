import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_theme.dart';

class ShellScreen extends StatelessWidget {
  const ShellScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 20),
          onPressed: () => context.pop(),
        ),
        title: const Text('SHELL', style: TextStyle(fontSize: 14, letterSpacing: 2)),
      ),
      body: const Center(
        child: Text(
          'Shell coming soon',
          style: TextStyle(color: AppTheme.textTertiary, fontSize: 14),
        ),
      ),
    );
  }
}
