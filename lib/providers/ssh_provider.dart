import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../models/ssh_credentials.dart';
import '../services/ssh_service.dart';

class SshState {
  final bool isConnected;
  final bool isConnecting;
  final SshCredentials? credentials;
  final Terminal? terminal;
  final String? error;

  const SshState({
    this.isConnected = false,
    this.isConnecting = false,
    this.credentials,
    this.terminal,
    this.error,
  });

  SshState copyWith({
    bool? isConnected,
    bool? isConnecting,
    SshCredentials? credentials,
    Terminal? terminal,
    String? error,
  }) {
    return SshState(
      isConnected: isConnected ?? this.isConnected,
      isConnecting: isConnecting ?? this.isConnecting,
      credentials: credentials ?? this.credentials,
      terminal: terminal ?? this.terminal,
      error: error,
    );
  }
}

class SshNotifier extends StateNotifier<SshState> {
  final SshService _service;

  SshNotifier(this._service) : super(const SshState());

  Future<void> loadSavedCredentials() async {
    final credentials = await _service.loadCredentials();
    if (credentials != null) {
      state = state.copyWith(credentials: credentials);
    }
  }

  Future<bool> connect(SshCredentials credentials, {bool remember = false}) async {
    state = state.copyWith(isConnecting: true, error: null);

    if (remember) {
      await _service.saveCredentials(credentials);
    } else {
      await _service.clearCredentials();
    }

    final success = await _service.connect(credentials);

    if (success) {
      state = SshState(
        isConnected: true,
        isConnecting: false,
        credentials: credentials,
        terminal: _service.terminal,
      );
      return true;
    } else {
      state = state.copyWith(
        isConnecting: false,
        error: 'Failed to connect to SSH server',
      );
      return false;
    }
  }

  void disconnect() {
    _service.disconnect();
    state = SshState(credentials: state.credentials);
  }

  void resize(int width, int height) {
    _service.resize(width, height);
  }
}

final sshServiceProvider = Provider<SshService>((ref) {
  return SshService();
});

final sshProvider = StateNotifierProvider<SshNotifier, SshState>((ref) {
  final service = ref.watch(sshServiceProvider);
  return SshNotifier(service);
});
