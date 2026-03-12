import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/cli_device.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../utils/app_snackbar.dart';

class DeviceConnectionScreen extends ConsumerStatefulWidget {
  const DeviceConnectionScreen({super.key});

  @override
  ConsumerState<DeviceConnectionScreen> createState() =>
      _DeviceConnectionScreenState();
}

class _DeviceConnectionScreenState
    extends ConsumerState<DeviceConnectionScreen> {
  bool _isScanning = false;
  bool _isPairing = false;
  String? _error;
  List<DiscoveredCliDevice> _devices = const [];

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    if (_isScanning) return;
    setState(() {
      _isScanning = true;
      _error = null;
    });

    try {
      final service = ref.read(lanDiscoveryServiceProvider);
      final devices = await service.scan();
      if (!mounted) return;
      setState(() {
        _devices = devices;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
      }
    }
  }

  Future<void> _selectDevice(DiscoveredCliDevice device) async {
    if (_isPairing) return;
    if (device.isPaired) {
      await ref.read(settingsProvider.notifier).selectCliDevice(device);
      if (!mounted) return;
      context.go('/agents');
      return;
    }

    final code = await _promptForCode(device);
    if (!mounted || code == null || code.isEmpty) {
      return;
    }

    setState(() => _isPairing = true);
    try {
      final paired = await ref
          .read(lanDiscoveryServiceProvider)
          .redeemPairing(device: device, code: code);
      await ref.read(settingsProvider.notifier).selectCliDevice(paired);
      if (!mounted) return;
      context.go('/agents');
    } catch (error) {
      if (!mounted) return;
      AppSnackBar.showError(context, 'Pairing failed: $error');
    } finally {
      if (mounted) {
        setState(() => _isPairing = false);
      }
    }
  }

  Future<String?> _promptForCode(DiscoveredCliDevice device) async {
    return showDialog<String>(
      context: context,
      builder: (context) {
        return _PairingCodeDialog(deviceName: device.deviceName);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'CONNECT',
          style: TextStyle(fontSize: 14, letterSpacing: 2),
        ),
        actions: [
          IconButton(
            onPressed: _isScanning ? null : _scan,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_isScanning)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: CircularProgressIndicator(color: AppTheme.accent),
              ),
            )
          else if (_devices.isEmpty)
            Container(
              decoration: BoxDecoration(
                color: AppTheme.surface,
                border: Border.all(color: AppTheme.border),
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Icon(
                    Icons.wifi_find,
                    color: AppTheme.textTertiary,
                    size: 36,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'No moCODE CLI devices found on this network.',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _error ??
                        'Make sure the CLI is running and your phone is on the same LAN.',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            ..._devices.map((device) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Material(
                  color: AppTheme.surface,
                  child: InkWell(
                    onTap: _isPairing ? null : () => _selectDevice(device),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: device.isPaired
                              ? AppTheme.accent
                              : AppTheme.border,
                        ),
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: AppTheme.background,
                              border: Border.all(color: AppTheme.border),
                            ),
                            child: Icon(
                              device.isPaired
                                  ? Icons.verified_user_outlined
                                  : Icons.computer_outlined,
                              color: device.isPaired
                                  ? AppTheme.accent
                                  : AppTheme.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  device.deviceName,
                                  style: const TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  device.subtitle,
                                  style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            device.isPaired ? 'PAIRED' : 'PAIR',
                            style: TextStyle(
                              color: device.isPaired
                                  ? AppTheme.accent
                                  : AppTheme.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _PairingCodeDialog extends StatefulWidget {
  final String deviceName;

  const _PairingCodeDialog({required this.deviceName});

  @override
  State<_PairingCodeDialog> createState() => _PairingCodeDialogState();
}

class _PairingCodeDialogState extends State<_PairingCodeDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      title: Text(
        'Pair ${widget.deviceName}',
        style: const TextStyle(color: AppTheme.textPrimary),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Run `mocode pair` on that machine, or `bun run cli -- pair` from the repo, then enter the 6-digit code here.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              maxLength: 6,
              autofocus: true,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Pairing code',
                counterText: '',
              ),
              onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('CANCEL'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('PAIR'),
        ),
      ],
    );
  }
}
