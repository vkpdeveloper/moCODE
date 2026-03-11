import 'dart:async';
import 'dart:math';

enum SshConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
}

enum ConnectionEvent {
  connect,
  disconnect,
  connectionLost,
  retry,
  maxRetriesReached,
}

class RetryConfig {
  final int maxRetries;
  final Duration baseDelay;
  final Duration maxDelay;
  final bool useJitter;

  const RetryConfig({
    this.maxRetries = 5,
    this.baseDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 30),
    this.useJitter = true,
  });
}

class ExponentialBackoff {
  final RetryConfig config;
  int _currentAttempt = 0;
  final Random _random = Random();

  ExponentialBackoff({this.config = const RetryConfig()});

  int get currentAttempt => _currentAttempt;
  bool get hasMoreRetries => _currentAttempt < config.maxRetries;

  Duration get nextDelay {
    if (!hasMoreRetries) {
      return Duration.zero;
    }

    final exponentialDelay = config.baseDelay.inMilliseconds *
        pow(2, _currentAttempt - 1).toInt();

    final cappedDelay = exponentialDelay.clamp(
      0,
      config.maxDelay.inMilliseconds,
    );

    if (config.useJitter) {
      final jitter = _random.nextInt(cappedDelay ~/ 2);
      return Duration(milliseconds: cappedDelay + jitter);
    }

    return Duration(milliseconds: cappedDelay);
  }

  void recordAttempt() {
    _currentAttempt++;
  }

  void reset() {
    _currentAttempt = 0;
  }

  Duration get totalDelay {
    int total = 0;
    for (int i = 0; i < config.maxRetries; i++) {
      final delay = config.baseDelay.inMilliseconds * pow(2, i).toInt();
      total += delay.clamp(0, config.maxDelay.inMilliseconds);
    }
    return Duration(milliseconds: total);
  }
}

class ConnectionStateMachine {
  final void Function(SshConnectionState oldState, SshConnectionState newState)?
      onStateChanged;
  final void Function(int attempt, Duration delay)? onRetry;
  final void Function()? onMaxRetriesReached;

  SshConnectionState _state = SshConnectionState.disconnected;
  final ExponentialBackoff _backoff;
  Timer? _retryTimer;
  Timer? _keepaliveTimer;

  ConnectionStateMachine({
    RetryConfig config = const RetryConfig(),
    this.onStateChanged,
    this.onRetry,
    this.onMaxRetriesReached,
  }) : _backoff = ExponentialBackoff(config: config);

  SshConnectionState get state => _state;
  int get currentRetryAttempt => _backoff.currentAttempt;
  bool get canRetry => _backoff.hasMoreRetries;

  void _setState(SshConnectionState newState) {
    if (_state == newState) return;
    final oldState = _state;
    _state = newState;
    onStateChanged?.call(oldState, newState);
  }

  Future<bool> connect(Future<bool> Function() connectFn) async {
    if (_state == SshConnectionState.connected ||
        _state == SshConnectionState.connecting) {
      return true;
    }

    _setState(SshConnectionState.connecting);
    _backoff.reset();

    try {
      final success = await connectFn();
      if (success) {
        _setState(SshConnectionState.connected);
        return true;
      } else {
        _handleConnectionFailure();
        return false;
      }
    } catch (e) {
      _handleConnectionFailure();
      return false;
    }
  }

  void _handleConnectionFailure() {
    _backoff.recordAttempt();

    if (!_backoff.hasMoreRetries) {
      _setState(SshConnectionState.disconnected);
      onMaxRetriesReached?.call();
      return;
    }

    _setState(SshConnectionState.reconnecting);
    final delay = _backoff.nextDelay;
    onRetry?.call(_backoff.currentAttempt, delay);

    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      if (_state == SshConnectionState.reconnecting) {
        _setState(SshConnectionState.disconnected);
      }
    });
  }

  void onConnectionLost() {
    if (_state != SshConnectionState.connected) return;
    _handleConnectionFailure();
  }

  Future<bool> reconnect(Future<bool> Function() reconnectFn) async {
    if (_state == SshConnectionState.connecting) {
      return false;
    }

    _setState(SshConnectionState.reconnecting);
    _backoff.reset();

    try {
      final success = await reconnectFn();
      if (success) {
        _setState(SshConnectionState.connected);
        return true;
      } else {
        _handleConnectionFailure();
        return false;
      }
    } catch (e) {
      _handleConnectionFailure();
      return false;
    }
  }

  void disconnect() {
    _retryTimer?.cancel();
    _keepaliveTimer?.cancel();
    _backoff.reset();
    _setState(SshConnectionState.disconnected);
  }

  void startKeepalive({
    required Future<bool> Function() checkConnection,
    Duration interval = const Duration(seconds: 30),
  }) {
    _keepaliveTimer?.cancel();
    _keepaliveTimer = Timer.periodic(interval, (_) async {
      if (_state != SshConnectionState.connected) return;
      try {
        final isAlive = await checkConnection();
        if (!isAlive) {
          onConnectionLost();
        }
      } catch (e) {
        onConnectionLost();
      }
    });
  }

  void stopKeepalive() {
    _keepaliveTimer?.cancel();
    _keepaliveTimer = null;
  }

  void dispose() {
    disconnect();
    _retryTimer?.cancel();
    _keepaliveTimer?.cancel();
  }
}
