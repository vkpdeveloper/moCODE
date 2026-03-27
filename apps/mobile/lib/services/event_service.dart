import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket/web_socket.dart';

import 'api_client.dart';
import 'app_logger.dart';

class EventService {
  EventService(this._apiClient);

  final ApiClient _apiClient;
  final StreamController<Map<String, dynamic>> _controller =
      StreamController<Map<String, dynamic>>.broadcast();
  final Set<String> _subscribedSessionIds = <String>{};
  final Map<String, Completer<Map<String, dynamic>>> _pendingRequests =
      <String, Completer<Map<String, dynamic>>>{};

  StreamSubscription<WebSocketEvent>? _eventSubscription;
  WebSocket? _socket;
  Timer? _reconnectTimer;
  bool _isConnecting = false;
  bool _isDisposed = false;
  bool _hasConnectedBefore = false;
  bool _emitReconnectOnNextConnect = false;
  bool _suppressDisconnectHandling = false;
  int _connectionGeneration = 0;

  Stream<Map<String, dynamic>> subscribe({String? directory}) {
    AppLogger.instance.debug(
      'Subscribed to realtime websocket',
      scope: 'realtime',
      data: {'directory': directory},
    );
    ensureConnected();
    return _controller.stream;
  }

  void retain(String directory) {
    ensureConnected();
  }

  void release(String directory, {Duration? grace}) {}

  Future<void> subscribeSession(String sessionId) async {
    if (sessionId.trim().isEmpty) {
      return;
    }
    final next = Set<String>.from(_subscribedSessionIds)..add(sessionId);
    setSubscribedSessionIds(next);
  }

  void setSubscribedSessionIds(Set<String> sessionIds) {
    final normalized = sessionIds
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    if (setEquals(_subscribedSessionIds, normalized)) {
      return;
    }
    _subscribedSessionIds
      ..clear()
      ..addAll(normalized);
    AppLogger.instance.info(
      'Updated websocket session subscriptions',
      scope: 'realtime',
      data: {'sessionIds': normalized.toList(growable: false)},
    );
    _refreshConnection(emitReconnected: false);
  }

  void resetConnection() {
    AppLogger.instance.info(
      'Resetting realtime websocket connection',
      scope: 'realtime',
    );
    _refreshConnection(emitReconnected: false);
  }

  void ensureConnected({bool force = false}) {
    if (_isDisposed || _isConnecting || _socket != null) {
      return;
    }
    final token = _apiClient.bearerToken;
    if (token == null || token.isEmpty) {
      AppLogger.instance.warning(
        'Realtime websocket skipped because token is missing',
        scope: 'realtime',
      );
      return;
    }
    if (!force && _subscribedSessionIds.isEmpty) {
      AppLogger.instance.debug(
        'Realtime websocket skipped because no sessions are subscribed',
        scope: 'realtime',
      );
      return;
    }
    unawaited(_connect(force: force));
  }

  Future<Map<String, dynamic>> sendRequest(
    Map<String, dynamic> message, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final requestId =
        message['requestId']?.toString() ??
        'req_${DateTime.now().microsecondsSinceEpoch}';
    final payload = Map<String, dynamic>.from(message)
      ..['requestId'] = requestId;
    await _waitForConnection(force: true);

    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[requestId] = completer;
    try {
      _socket!.sendText(jsonEncode(payload));
    } catch (error, stackTrace) {
      _pendingRequests.remove(requestId);
      AppLogger.instance.error(
        'Failed to send realtime websocket request',
        scope: 'realtime',
        error: error,
        stackTrace: stackTrace,
        data: {'type': payload['type'], 'requestId': requestId},
      );
      rethrow;
    }

    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pendingRequests.remove(requestId);
        throw TimeoutException(
          'Timed out waiting for websocket response: ${payload['type']}',
        );
      },
    );
  }

  Future<Map<String, dynamic>> promptSession(
    String sessionId, {
    String? text,
    List<Map<String, dynamic>>? prompt,
  }) {
    final request = <String, dynamic>{
      'type': 'prompt_session',
      'sessionId': sessionId,
      if (text != null && text.trim().isNotEmpty) 'text': text.trim(),
      if (prompt != null && prompt.isNotEmpty) 'prompt': prompt,
    };
    return sendRequest(request);
  }

  Future<Map<String, dynamic>> cancelSession(String sessionId) {
    return sendRequest({'type': 'cancel_session', 'sessionId': sessionId});
  }

  Future<Map<String, dynamic>> replyPermission(
    String sessionId,
    String permissionRequestId, {
    required Map<String, dynamic> outcome,
  }) {
    return sendRequest({
      'type': 'reply_permission',
      'sessionId': sessionId,
      'permissionRequestId': permissionRequestId,
      'outcome': outcome,
    });
  }

  Future<Map<String, dynamic>> replyQuestion(
    String sessionId,
    String questionRequestId, {
    required Map<String, dynamic> outcome,
  }) {
    return sendRequest({
      'type': 'reply_question',
      'sessionId': sessionId,
      'questionRequestId': questionRequestId,
      'outcome': outcome,
    });
  }

  Future<void> _waitForConnection({bool force = false}) async {
    final token = _apiClient.bearerToken;
    if (token == null || token.isEmpty) {
      throw StateError('Realtime websocket token is missing.');
    }
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    ensureConnected(force: force);
    while (!_isDisposed && (_isConnecting || _socket == null)) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('Timed out waiting for realtime websocket.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (!_isConnecting && _socket == null) {
        ensureConnected(force: force);
      }
    }
    if (_socket == null) {
      throw StateError('Realtime websocket is not connected.');
    }
  }

  Future<void> _connect({bool force = false}) async {
    final generation = ++_connectionGeneration;
    final sessionIds = _subscribedSessionIds.toList(growable: false)..sort();
    final uri = _apiClient.buildWebSocketUri(
      '/v1/realtime',
      queryParameters: {'token': _apiClient.bearerToken},
    );
    _isConnecting = true;

    try {
      AppLogger.instance.info(
        'Opening realtime websocket',
        scope: 'realtime',
        data: {'uri': uri.toString(), 'sessionIds': sessionIds},
      );

      final socket = await WebSocket.connect(uri);
      final subscription = socket.events.listen(
        _handleSocketEvent,
        onDone: _handleDisconnect,
      );

      if (_isDisposed || generation != _connectionGeneration) {
        await subscription.cancel();
        await socket.close();
        _isConnecting = false;
        return;
      }

      _socket = socket;
      _eventSubscription = subscription;
      _isConnecting = false;

      for (final sessionId in sessionIds) {
        _sendFireAndForget({
          'type': 'subscribe_session',
          'sessionId': sessionId,
        });
      }

      if (_emitReconnectOnNextConnect &&
          _hasConnectedBefore &&
          !_controller.isClosed) {
        _controller.add(const {'type': '__reconnected__'});
      }
      _emitReconnectOnNextConnect = false;
      _hasConnectedBefore = true;
      AppLogger.instance.info(
        'Realtime websocket connected',
        scope: 'realtime',
        data: {'subscriptions': sessionIds},
      );
    } catch (error, stackTrace) {
      if (_isDisposed || generation != _connectionGeneration) {
        _isConnecting = false;
        return;
      }
      _isConnecting = false;
      AppLogger.instance.error(
        'Realtime websocket connection failed',
        scope: 'realtime',
        error: error,
        stackTrace: stackTrace,
      );
      if (!_controller.isClosed) {
        _controller.addError(error, stackTrace);
      }
      _scheduleReconnect();
    }
  }

  void _handleSocketEvent(WebSocketEvent event) {
    switch (event) {
      case TextDataReceived(text: final text):
        _handleMessage(text);
      case BinaryDataReceived():
        return;
      case CloseReceived(code: final code, reason: final reason):
        AppLogger.instance.warning(
          'Realtime websocket closed by peer',
          scope: 'realtime',
          data: {'code': code, 'reason': reason},
        );
        _handleDisconnect();
    }
  }

  void _handleMessage(String text) {
    Map<String, dynamic> message;
    try {
      message = jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final payloadRaw = message['payload'];
    final payload = payloadRaw is Map<String, dynamic>
        ? payloadRaw
        : payloadRaw is Map
        ? Map<String, dynamic>.from(payloadRaw)
        : <String, dynamic>{};
    final requestId = payload['requestId']?.toString();

    AppLogger.instance.debug(
      'Realtime websocket message received',
      scope: 'realtime',
      data: {
        'type': message['type'],
        'payload': AppLogger.instance.sanitize(payload),
      },
    );

    if (requestId != null && requestId.isNotEmpty) {
      final pending = _pendingRequests.remove(requestId);
      if (pending != null && !pending.isCompleted) {
        if (message['type'] == 'request_error') {
          pending.completeError(
            StateError(
              payload['error']?.toString() ?? 'Realtime request failed',
            ),
          );
        } else {
          pending.complete(message);
        }
      }
    }

    if (!_controller.isClosed && message['type'] != 'request_error') {
      _controller.add(message);
    }
  }

  void _handleDisconnect() {
    if (_suppressDisconnectHandling) {
      return;
    }
    AppLogger.instance.warning(
      'Realtime websocket disconnected',
      scope: 'realtime',
    );
    _disconnect(failPending: true);
    _emitReconnectOnNextConnect = true;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_isDisposed || _reconnectTimer != null) {
      return;
    }
    _reconnectTimer = Timer(const Duration(seconds: 2), () {
      _reconnectTimer = null;
      ensureConnected(force: _subscribedSessionIds.isNotEmpty);
    });
  }

  void _refreshConnection({required bool emitReconnected}) {
    _emitReconnectOnNextConnect =
        emitReconnected || (_emitReconnectOnNextConnect && _hasConnectedBefore);
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _connectionGeneration += 1;
    _disconnect(failPending: true);
    ensureConnected(force: _subscribedSessionIds.isNotEmpty);
  }

  void _disconnect({required bool failPending}) {
    final subscription = _eventSubscription;
    final socket = _socket;
    _eventSubscription = null;
    _socket = null;

    if (failPending) {
      final pending = Map<String, Completer<Map<String, dynamic>>>.from(
        _pendingRequests,
      );
      _pendingRequests.clear();
      for (final entry in pending.entries) {
        if (!entry.value.isCompleted) {
          entry.value.completeError(
            StateError('Realtime websocket disconnected.'),
          );
        }
      }
    }

    if (subscription != null || socket != null) {
      _suppressDisconnectHandling = true;
      Future<void>(() async {
        try {
          await subscription?.cancel();
        } finally {
          try {
            await socket?.close();
          } catch (_) {
            // ignore close failures
          } finally {
            _suppressDisconnectHandling = false;
          }
        }
      });
    }
  }

  void _sendFireAndForget(Map<String, dynamic> message) {
    try {
      _socket?.sendText(jsonEncode(message));
    } catch (error, stackTrace) {
      AppLogger.instance.error(
        'Failed to send fire-and-forget websocket message',
        scope: 'realtime',
        error: error,
        stackTrace: stackTrace,
        data: {'type': message['type']},
      );
    }
  }

  void dispose() {
    _isDisposed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _connectionGeneration += 1;
    _disconnect(failPending: true);
    if (!_controller.isClosed) {
      _controller.close();
    }
  }
}
