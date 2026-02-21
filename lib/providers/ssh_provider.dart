import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:xterm/xterm.dart';

import '../models/ssh_credentials.dart';
import '../services/ssh_service.dart';
import '../services/connection_manager.dart';

class SshState {
  final bool isConnected;
  final bool isConnecting;
  final bool isReconnecting;
  final SshCredentials? credentials;
  final Terminal? terminal;
  final String? error;
  final int retryAttempt;
  final Duration? nextRetryDelay;
  final SshConnectionState connectionState;

  const SshState({
    this.isConnected = false,
    this.isConnecting = false,
    this.isReconnecting = false,
    this.credentials,
    this.terminal,
    this.error,
    this.retryAttempt = 0,
    this.nextRetryDelay,
    this.connectionState = SshConnectionState.disconnected,
  });

  SshState copyWith({
    bool? isConnected,
    bool? isConnecting,
    bool? isReconnecting,
    SshCredentials? credentials,
    Terminal? terminal,
    String? error,
    int? retryAttempt,
    Duration? nextRetryDelay,
    SshConnectionState? connectionState,
  }) {
    return SshState(
      isConnected: isConnected ?? this.isConnected,
      isConnecting: isConnecting ?? this.isConnecting,
      isReconnecting: isReconnecting ?? this.isReconnecting,
      credentials: credentials ?? this.credentials,
      terminal: terminal ?? this.terminal,
      error: error,
      retryAttempt: retryAttempt ?? this.retryAttempt,
      nextRetryDelay: nextRetryDelay,
      connectionState: connectionState ?? this.connectionState,
    );
  }
}

class SshNotifier extends StateNotifier<SshState> {
  final SshService _service;
  StreamSubscription<SshConnectionState>? _connectionStateSubscription;
  StreamSubscription<ReconnectAttempt>? _reconnectAttemptSubscription;

  SshNotifier(this._service) : super(const SshState()) {
    _setupSshConnectionStateListener();
  }

  void _setupSshConnectionStateListener() {
    _connectionStateSubscription = _service.connectionStateStream.listen((
      connState,
    ) {
      switch (connState) {
        case SshConnectionState.connected:
          state = state.copyWith(
            isConnected: true,
            isConnecting: false,
            isReconnecting: false,
            error: null,
            connectionState: connState,
          );
          break;
        case SshConnectionState.disconnected:
          state = state.copyWith(
            isConnected: false,
            isConnecting: false,
            isReconnecting: false,
            connectionState: connState,
          );
          break;
        case SshConnectionState.connecting:
          state = state.copyWith(
            isConnecting: true,
            connectionState: connState,
          );
          break;
        case SshConnectionState.reconnecting:
          state = state.copyWith(
            isReconnecting: true,
            connectionState: connState,
          );
          break;
      }
    });

    _reconnectAttemptSubscription = _service.reconnectAttemptStream.listen((
      attempt,
    ) {
      state = state.copyWith(
        retryAttempt: attempt.attempt,
        nextRetryDelay: attempt.delay,
      );
    });
  }

  Future<void> loadSavedCredentials() async {
    final credentials = await _service.loadCredentials();
    if (credentials != null) {
      state = state.copyWith(credentials: credentials);
    }
  }

  Future<bool> connect(
    SshCredentials credentials, {
    bool remember = false,
  }) async {
    state = state.copyWith(
      isConnecting: true,
      error: null,
      retryAttempt: 0,
      nextRetryDelay: null,
    );

    if (remember) {
      await _service.saveCredentials(credentials);
    } else {
      await _service.clearCredentials();
    }

    String? connectionError;
    final success = await _service.connect(
      credentials,
      onError: (error) => connectionError = error,
    );

    if (success) {
      state = SshState(
        isConnected: true,
        isConnecting: false,
        credentials: credentials,
        terminal: _service.terminal,
        connectionState: SshConnectionState.connected,
      );
      return true;
    } else {
      state = state.copyWith(
        isConnecting: false,
        error: connectionError ?? 'Failed to connect to SSH server',
      );
      return false;
    }
  }

  Future<bool> reconnect() async {
    if (state.credentials == null) {
      state = state.copyWith(
        error: 'No credentials available for reconnection',
      );
      return false;
    }

    state = state.copyWith(isReconnecting: true, error: null, retryAttempt: 0);

    final success = await _service.reconnect();

    if (success) {
      state = state.copyWith(
        isConnected: true,
        isReconnecting: false,
        terminal: _service.terminal,
      );
      return true;
    } else {
      state = state.copyWith(
        isReconnecting: false,
        error: 'Failed to reconnect to SSH server',
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

  bool get canReconnect =>
      state.credentials != null &&
      (state.connectionState == SshConnectionState.disconnected ||
          state.connectionState == SshConnectionState.reconnecting);

  void clearError() {
    state = state.copyWith(error: null);
  }

  Future<bool> checkConnection() async {
    try {
      return await _service.checkSftpConnection();
    } catch (e) {
      return false;
    }
  }

  Future<bool> checkSshConnection() async {
    try {
      return await _service.checkSshConnection();
    } catch (e) {
      return false;
    }
  }

  @override
  void dispose() {
    _connectionStateSubscription?.cancel();
    _reconnectAttemptSubscription?.cancel();
    super.dispose();
  }
}

final sshServiceProvider = Provider<SshService>((ref) {
  final service = SshService();
  ref.onDispose(() => service.dispose());
  return service;
});

final sshProvider = StateNotifierProvider<SshNotifier, SshState>((ref) {
  final service = ref.watch(sshServiceProvider);
  return SshNotifier(service);
});
