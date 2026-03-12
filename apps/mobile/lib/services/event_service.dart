import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'app_logger.dart';

class EventService {
  EventService(this._apiClient);

  final ApiClient _apiClient;
  final StreamController<Map<String, dynamic>> _controller =
      StreamController<Map<String, dynamic>>.broadcast();
  final Set<String> _subscribedSessionIds = <String>{};

  StreamSubscription<String>? _lineSubscription;
  HttpClient? _httpClient;
  Timer? _reconnectTimer;
  bool _isConnecting = false;
  bool _isDisposed = false;
  bool _hasConnectedBefore = false;
  bool _emitReconnectOnNextConnect = false;
  bool _suppressDisconnectHandling = false;
  int _connectionGeneration = 0;

  Stream<Map<String, dynamic>> subscribe({String? directory}) {
    AppLogger.instance.debug(
      'Subscribed to realtime event stream',
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
      'Updated SSE session subscriptions',
      scope: 'realtime',
      data: {'sessionIds': normalized.toList(growable: false)},
    );
    _refreshConnection(emitReconnected: false);
  }

  void resetConnection() {
    AppLogger.instance.info(
      'Resetting realtime connection',
      scope: 'realtime',
    );
    _refreshConnection(emitReconnected: false);
  }

  void ensureConnected() {
    if (_isDisposed || _isConnecting || _lineSubscription != null) {
      return;
    }
    final token = _apiClient.bearerToken;
    if (token == null || token.isEmpty) {
      AppLogger.instance.warning(
        'Realtime connection skipped because token is missing',
        scope: 'realtime',
      );
      return;
    }
    if (_subscribedSessionIds.isEmpty) {
      AppLogger.instance.debug(
        'Realtime connection skipped because no sessions are subscribed',
        scope: 'realtime',
      );
      return;
    }
    unawaited(_connect());
  }

  Future<void> _connect() async {
    final generation = ++_connectionGeneration;
    final sessionIds = _subscribedSessionIds.toList(growable: false)..sort();
    final uri = _apiClient.buildUri(
      '/v1/events',
      queryParameters: {'sessionId': sessionIds.join(',')},
    );
    _isConnecting = true;

    try {
      AppLogger.instance.info(
        'Opening realtime SSE stream',
        scope: 'realtime',
        data: {
          'path': '/v1/events',
          'sessionIds': sessionIds,
        },
      );

      final client = HttpClient();
      _httpClient = client;
      final request = await client.getUrl(uri);
      final token = _apiClient.bearerToken;
      if (token != null && token.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');

      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        final body = await utf8.decoder.bind(response).join();
        throw HttpException(
          'Realtime SSE request failed (${response.statusCode}): ${body.trim()}',
          uri: uri,
        );
      }

      String? eventType;
      final dataLines = <String>[];

      void dispatchEvent() {
        if (dataLines.isEmpty) {
          eventType = null;
          return;
        }

        final text = dataLines.join('\n');
        dataLines.clear();
        _handleMessage(text, eventType: eventType);
        eventType = null;
      }

      final subscription = utf8
          .decoder
          .bind(response)
          .transform(const LineSplitter())
          .listen(
            (line) {
              if (line.isEmpty) {
                dispatchEvent();
                return;
              }
              if (line.startsWith(':')) {
                return;
              }
              if (line.startsWith('event:')) {
                eventType = line.substring('event:'.length).trim();
                return;
              }
              if (line.startsWith('data:')) {
                dataLines.add(line.substring('data:'.length).trimLeft());
              }
            },
            onDone: _handleDisconnect,
            onError: (Object error, StackTrace stackTrace) {
              if (!_controller.isClosed) {
                _controller.addError(error, stackTrace);
              }
              _handleDisconnect();
            },
            cancelOnError: false,
          );

      if (_isDisposed || generation != _connectionGeneration) {
        await subscription.cancel();
        client.close(force: true);
        _isConnecting = false;
        return;
      }

      _lineSubscription = subscription;
      _isConnecting = false;

      if (_emitReconnectOnNextConnect &&
          _hasConnectedBefore &&
          !_controller.isClosed) {
        _controller.add(const {'type': '__reconnected__'});
      }
      _emitReconnectOnNextConnect = false;
      _hasConnectedBefore = true;
      AppLogger.instance.info(
        'Realtime SSE connected',
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
        'Realtime SSE connection failed',
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

  void _handleMessage(String text, {String? eventType}) {
    Map<String, dynamic> message;
    try {
      message = jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    if ((message['type'] == null || message['type'].toString().isEmpty) &&
        eventType != null &&
        eventType.isNotEmpty) {
      message['type'] = eventType;
    }

    final payload = message['payload'];
    AppLogger.instance.debug(
      'Realtime SSE message received',
      scope: 'realtime',
      data: {
        'type': message['type'],
        'payload': AppLogger.instance.sanitize(payload),
      },
    );

    if (!_controller.isClosed) {
      _controller.add(message);
    }
  }

  void _handleDisconnect() {
    if (_suppressDisconnectHandling) {
      return;
    }
    AppLogger.instance.warning(
      'Realtime SSE disconnected',
      scope: 'realtime',
    );
    _disconnect();
    _emitReconnectOnNextConnect = true;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_isDisposed ||
        _reconnectTimer != null ||
        _subscribedSessionIds.isEmpty) {
      return;
    }
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      _reconnectTimer = null;
      AppLogger.instance.info(
        'Retrying realtime SSE connection',
        scope: 'realtime',
      );
      ensureConnected();
    });
  }

  void _refreshConnection({required bool emitReconnected}) {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _emitReconnectOnNextConnect = emitReconnected;
    _connectionGeneration += 1;
    _disconnect();
    if (!_isDisposed) {
      ensureConnected();
    }
  }

  void _disconnect() {
    _suppressDisconnectHandling = true;
    _lineSubscription?.cancel();
    _lineSubscription = null;
    _httpClient?.close(force: true);
    _httpClient = null;
    _isConnecting = false;
    scheduleMicrotask(() {
      _suppressDisconnectHandling = false;
    });
  }

  void dispose() {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _disconnect();
    _controller.close();
    AppLogger.instance.info('Disposed realtime service', scope: 'realtime');
  }
}
