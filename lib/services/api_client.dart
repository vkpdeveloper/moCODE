import 'package:dio/dio.dart';

class ApiClient {
  late Dio _dio;
  String _baseUrl;

  ApiClient({String baseUrl = 'http://127.0.0.1:4096'}) : _baseUrl = baseUrl {
    _dio = Dio(
      BaseOptions(
        baseUrl: _baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(minutes: 5),
        sendTimeout: const Duration(minutes: 2),
        headers: {'Content-Type': 'application/json'},
        responseType: ResponseType.bytes,
      ),
    );
  }

  void updateBaseUrl(String url) {
    _baseUrl = url;
    _dio.options.baseUrl = url;
  }

  String get baseUrl => _baseUrl;
  Dio get dio => _dio;

  String buildWsUrl(String path, {Map<String, dynamic>? queryParameters}) {
    var url = _baseUrl;
    if (url.startsWith('http://')) {
      url = 'ws://${url.substring('http://'.length)}';
    } else if (url.startsWith('https://')) {
      url = 'wss://${url.substring('https://'.length)}';
    }
    if (!path.startsWith('/')) {
      url += '/$path';
    } else {
      url += path;
    }
    if (queryParameters != null && queryParameters.isNotEmpty) {
      final filtered = <String, String>{};
      queryParameters.forEach((key, value) {
        if (value == null) return;
        filtered[key] = value.toString();
      });
      if (filtered.isNotEmpty) {
        final query = Uri(queryParameters: filtered).query;
        url += '?$query';
      }
    }
    return url;
  }
}
