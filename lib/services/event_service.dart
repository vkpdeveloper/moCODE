import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import 'api_client.dart';

class EventService {
  final ApiClient _apiClient;
  StreamController<Map<String, dynamic>>? _controller;
  bool _isConnected = false;

  EventService(this._apiClient);

  bool get isConnected => _isConnected;

  Stream<Map<String, dynamic>> subscribe({String? directory}) {
    _controller?.close();
    _controller = StreamController<Map<String, dynamic>>.broadcast();
    _connect(directory: directory);
    return _controller!.stream;
  }

  Future<void> _connect({String? directory}) async {
    _isConnected = false;
    try {
      final response = await _apiClient.dio.get<ResponseBody>(
        '/event',
        queryParameters: {
          'directory': ?directory,
        },
        options: Options(
          responseType: ResponseType.stream,
          receiveTimeout: Duration.zero,
        ),
      );

      _isConnected = true;
      final stream = response.data!.stream;
      String buffer = '';

      await for (final chunk in stream) {
        buffer += utf8.decode(chunk);
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
              final parsed = json.decode(data) as Map<String, dynamic>;
              _controller?.add(parsed);
            } on FormatException {
              // skip malformed events
            }
          }
        }
      }
    } on DioException catch (e) {
      _isConnected = false;
      if (!(_controller?.isClosed ?? true)) {
        _controller?.addError(e);
        await Future<void>.delayed(const Duration(seconds: 3));
        if (!(_controller?.isClosed ?? true)) {
          _connect(directory: directory);
        }
      }
    } catch (e) {
      _isConnected = false;
      if (!(_controller?.isClosed ?? true)) {
        _controller?.addError(e);
      }
    }
  }

  void dispose() {
    _isConnected = false;
    _controller?.close();
    _controller = null;
  }
}
