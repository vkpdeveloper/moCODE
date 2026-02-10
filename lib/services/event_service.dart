import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import 'api_client.dart';
import '../utils/json_parser.dart';

class EventService {
  final ApiClient _apiClient;
  final Map<String, _EventConnection> _connections = {};

  EventService(this._apiClient);

  Stream<Map<String, dynamic>> subscribe({String? directory}) {
    final key = _directoryKey(directory);
    final connection = _connections.putIfAbsent(
      key,
      () => _EventConnection(_apiClient, directory: directory),
    );
    connection.ensureConnected();
    return connection.stream;
  }

  void retain(String directory) {
    final key = _directoryKey(directory);
    final connection = _connections.putIfAbsent(
      key,
      () => _EventConnection(_apiClient, directory: directory),
    );
    connection.retain();
  }

  void release(String directory, {Duration? grace}) {
    final key = _directoryKey(directory);
    final connection = _connections[key];
    if (connection == null) return;
    connection.release(grace: grace);
    if (connection.isDisposed) {
      _connections.remove(key);
    }
  }

  void dispose() {
    for (final connection in _connections.values) {
      connection.dispose();
    }
    _connections.clear();
  }

  String _directoryKey(String? directory) => directory ?? '__global__';
}

class _EventConnection {
  final ApiClient _apiClient;
  final String? directory;
  final StreamController<Map<String, dynamic>> _controller;
  int _retainCount = 0;
  bool _isConnected = false;
  bool _isDisposed = false;
  bool _isConnecting = false;
  Timer? _closeTimer;

  _EventConnection(this._apiClient, {required this.directory})
    : _controller = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get stream => _controller.stream;

  bool get isDisposed => _isDisposed;

  void retain() {
    if (_isDisposed) return;
    _retainCount += 1;
    _closeTimer?.cancel();
    ensureConnected();
  }

  void release({Duration? grace}) {
    if (_isDisposed) return;
    _retainCount = (_retainCount - 1).clamp(0, 1 << 30).toInt();
    if (_retainCount > 0 || _controller.hasListener) return;
    if (grace == null || grace == Duration.zero) {
      dispose();
      return;
    }
    _closeTimer?.cancel();
    _closeTimer = Timer(grace, () {
      if (_retainCount == 0 && !_controller.hasListener) {
        dispose();
      }
    });
  }

  void ensureConnected() {
    if (_isDisposed || _isConnecting || _isConnected) return;
    if (_retainCount == 0 && !_controller.hasListener) return;
    _connect();
  }

  Future<void> _connect() async {
    _isConnecting = true;
    _isConnected = false;
    try {
      final response = await _apiClient.dio.get<ResponseBody>(
        '/event',
        queryParameters: {'directory': ?directory},
        options: Options(
          responseType: ResponseType.stream,
          receiveTimeout: Duration.zero,
        ),
      );

      _isConnected = true;
      _isConnecting = false;
      final stream = response.data!.stream;
      String buffer = '';

      await for (final chunk in stream) {
        if (_isDisposed) return;
        buffer += utf8.decode(chunk as List<int>);
        final parts = buffer.split('\n\n');
        buffer = parts.removeLast();

        for (final part in parts) {
          final lines = part.split('\n');
          String? data;
          for (final line in lines) {
            if (line.startsWith('data: ')) {
              data = line.substring(6);
            }
          }
          if (data != null && data.isNotEmpty) {
            try {
              final parsed = parseJsonObjectBytes(utf8.encode(data));
              if (!_controller.isClosed) {
                _controller.add(parsed);
              }
            } on FormatException {
              // skip malformed events
            }
          }
        }
      }
    } on DioException catch (e) {
      _isConnected = false;
      _isConnecting = false;
      if (!_controller.isClosed) {
        _controller.addError(e);
      }
      await _retryConnect();
    } catch (e) {
      _isConnected = false;
      _isConnecting = false;
      if (!_controller.isClosed) {
        _controller.addError(e);
      }
      await _retryConnect();
    }
  }

  Future<void> _retryConnect() async {
    if (_isDisposed) return;
    if (_retainCount == 0 && !_controller.hasListener) return;
    await Future<void>.delayed(const Duration(seconds: 3));
    if (_isDisposed) return;
    ensureConnected();
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _isConnected = false;
    _closeTimer?.cancel();
    _controller.close();
  }
}
