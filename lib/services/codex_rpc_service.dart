import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../utils/app_logger.dart';

class CodexRpcException implements Exception {
  const CodexRpcException({
    required this.code,
    required this.message,
    this.data,
  });

  final int? code;
  final String message;
  final dynamic data;

  bool contains(String text) {
    return message.toLowerCase().contains(text.toLowerCase());
  }

  @override
  String toString() {
    if (code == null) return message;
    return '[$code] $message';
  }
}

class CodexRpcService {
  CodexRpcService({
    required this.host,
    required this.port,
    this.clientName = 'mocode',
    this.clientVersion = '1.0.0',
  });

  final String host;
  final int port;
  final String clientName;
  final String clientVersion;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  int _requestCounter = 0;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  bool _initialized = false;
  bool _connecting = false;

  final _notifications = StreamController<Map<String, dynamic>>.broadcast();
  final _serverRequests = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get notifications => _notifications.stream;
  Stream<Map<String, dynamic>> get serverRequests => _serverRequests.stream;

  Uri get _uri {
    final normalizedHost = host.trim() == '0.0.0.0' ? '127.0.0.1' : host.trim();
    return Uri.parse('ws://$normalizedHost:$port');
  }

  Future<void> ensureConnected() async {
    AppLogger.info(
      'codex.rpc',
      'ensureConnected:start',
      data: {'host': host, 'port': port, 'initialized': _initialized},
    );
    if (_initialized) return;
    if (_connecting) {
      while (_connecting) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
      if (_initialized) return;
    }

    _connecting = true;
    try {
      await _connect();
      await _initialize();
      _initialized = true;
      AppLogger.info('codex.rpc', 'ensureConnected:ready');
    } finally {
      _connecting = false;
    }
  }

  Future<void> _connect() async {
    AppLogger.info('codex.rpc', 'ws:connect', data: {'uri': _uri.toString()});
    _channel?.sink.close();
    await _sub?.cancel();

    _channel = WebSocketChannel.connect(_uri);
    _sub = _channel!.stream.listen(
      _onMessage,
      onDone: _onDisconnected,
      onError: (Object error, StackTrace st) {
        AppLogger.error(
          'codex.rpc',
          'ws:error',
          data: {'error': error.toString()},
        );
        debugPrint('[CodexRpcService] socket error: $error');
        _onDisconnected();
      },
    );
  }

  void _onDisconnected() {
    AppLogger.warn('codex.rpc', 'ws:disconnected');
    _initialized = false;
    for (final pending in _pending.values) {
      if (!pending.isCompleted) {
        pending.completeError(
          StateError('Disconnected from Codex app server'),
        );
      }
    }
    _pending.clear();
  }

  void _onMessage(dynamic raw) {
    if (raw is! String) return;
    try {
      final data = jsonDecode(raw);
      if (data is! Map) return;
      final map = Map<String, dynamic>.from(data);

      final id = map['id'];
      if (id is num && (map.containsKey('result') || map.containsKey('error'))) {
        AppLogger.debug(
          'codex.rpc',
          'rpc:response',
          data: {
            'id': id,
            'hasResult': map.containsKey('result'),
            'hasError': map.containsKey('error'),
          },
        );
        final completer = _pending.remove(id.toInt());
        if (completer == null) return;
        if (map.containsKey('error')) {
          final errorRaw = map['error'];
          if (errorRaw is Map) {
            final error = Map<String, dynamic>.from(errorRaw);
            completer.completeError(
              CodexRpcException(
                code: (error['code'] as num?)?.toInt(),
                message:
                    error['message']?.toString() ?? 'Unknown JSON-RPC error',
                data: error['data'],
              ),
            );
          } else {
            completer.completeError(
              CodexRpcException(code: null, message: 'Unknown JSON-RPC error'),
            );
          }
        } else {
          final result = map['result'];
          if (result is Map<String, dynamic>) {
            completer.complete(result);
          } else if (result is Map) {
            completer.complete(Map<String, dynamic>.from(result));
          } else {
            completer.complete(<String, dynamic>{'value': result});
          }
        }
        return;
      }

      final method = map['method'];
      if (method is! String) return;

      // server-initiated request
      if (map.containsKey('id')) {
        AppLogger.info(
          'codex.rpc',
          'rpc:serverRequest',
          data: {'method': method, 'id': map['id']},
        );
        _serverRequests.add(map);
        return;
      }

      AppLogger.debug(
        'codex.rpc',
        'rpc:notification',
        data: {'method': method},
      );
      _notifications.add(map);
    } catch (error) {
      AppLogger.error(
        'codex.rpc',
        'rpc:parseError',
        data: {'error': error.toString()},
      );
      debugPrint('[CodexRpcService] failed to parse message: $error');
    }
  }

  Future<void> _initialize() async {
    AppLogger.info('codex.rpc', 'initialize:send');
    await _callInternal(
      'initialize',
      {
        'clientInfo': {
          'name': clientName,
          'title': 'moCODE',
          'version': clientVersion,
        },
        'capabilities': {
          'experimentalApi': true,
          'optOutNotificationMethods': <String>[],
        },
      },
      ensureConnection: false,
    );

    _sendNotification('initialized');
    AppLogger.info('codex.rpc', 'initialize:completed');
  }

  Future<Map<String, dynamic>> call(
    String method,
    Map<String, dynamic>? params, {
    Duration timeout = const Duration(seconds: 20),
  }) {
    return _callInternal(
      method,
      params,
      timeout: timeout,
      ensureConnection: true,
    );
  }

  Future<Map<String, dynamic>> _callInternal(
    String method,
    Map<String, dynamic>? params, {
    required bool ensureConnection,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (ensureConnection) {
      await ensureConnected();
    }
    final id = ++_requestCounter;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;

    final payload = <String, dynamic>{
      'id': id,
      'method': method,
      'params': params,
    };

    AppLogger.debug(
      'codex.rpc',
      'rpc:request',
      data: {
        'id': id,
        'method': method,
        'paramKeys': params?.keys.toList() ?? const <String>[],
      },
    );
    _channel!.sink.add(jsonEncode(payload));

    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      _pending.remove(id);
      AppLogger.error(
        'codex.rpc',
        'rpc:timeout',
        data: {'id': id, 'method': method, 'timeoutMs': timeout.inMilliseconds},
      );
      throw TimeoutException('Timed out waiting for $method');
    }
  }

  Future<void> respond(
    dynamic id,
    Map<String, dynamic>? result,
  ) async {
    await ensureConnected();
    final payload = <String, dynamic>{
      'id': id,
      'result': result ?? <String, dynamic>{},
    };
    AppLogger.debug(
      'codex.rpc',
      'rpc:respond',
      data: {'id': id, 'keys': (result ?? const {}).keys.toList()},
    );
    _channel!.sink.add(jsonEncode(payload));
  }

  void _sendNotification(String method, [Map<String, dynamic>? params]) {
    final payload = <String, dynamic>{'method': method};
    if (params != null) payload['params'] = params;
    AppLogger.debug(
      'codex.rpc',
      'rpc:notify',
      data: {'method': method, 'hasParams': params != null},
    );
    _channel?.sink.add(jsonEncode(payload));
  }

  Future<void> dispose() async {
    _initialized = false;
    await _sub?.cancel();
    _sub = null;
    await _notifications.close();
    await _serverRequests.close();
    await _channel?.sink.close();
    _channel = null;
  }
}
