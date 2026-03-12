import 'package:dio/dio.dart';

import 'app_logger.dart';

class ApiClient {
  late Dio _dio;
  String _baseUrl;
  String? _bearerToken;

  ApiClient({String baseUrl = 'http://127.0.0.1:4058', String? bearerToken})
    : _baseUrl = baseUrl,
      _bearerToken = bearerToken {
    _dio = Dio(
      BaseOptions(
        baseUrl: _baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(minutes: 5),
        sendTimeout: const Duration(minutes: 2),
        headers: _headers(),
        responseType: ResponseType.bytes,
      ),
    );
    _dio.interceptors.add(AppLogInterceptor(clientName: 'cli'));
    AppLogger.instance.info(
      'CLI API client initialized',
      scope: 'apiClient',
      data: {'baseUrl': _baseUrl, 'hasBearerToken': bearerToken?.isNotEmpty == true},
    );
  }

  Map<String, String> _headers() {
    return {
      'Content-Type': 'application/json',
      if (_bearerToken != null && _bearerToken!.isNotEmpty)
        'Authorization': 'Bearer $_bearerToken',
    };
  }

  void updateBaseUrl(String url) {
    _baseUrl = url;
    _dio.options.baseUrl = url;
    AppLogger.instance.info(
      'CLI API base URL updated',
      scope: 'apiClient',
      data: {'baseUrl': url},
    );
  }

  void updateBearerToken(String? token) {
    _bearerToken = token;
    _dio.options.headers = _headers();
    AppLogger.instance.info(
      'CLI API bearer token updated',
      scope: 'apiClient',
      data: {'hasBearerToken': token?.isNotEmpty == true},
    );
  }

  String get baseUrl => _baseUrl;
  String? get bearerToken => _bearerToken;
  Dio get dio => _dio;

  Uri buildUri(String path, {Map<String, dynamic>? queryParameters}) {
    final resolved = Uri.parse(_baseUrl).resolve(
      path.startsWith('/') ? path.substring(1) : path,
    );
    final filtered = <String, String>{};
    if (queryParameters != null && queryParameters.isNotEmpty) {
      queryParameters.forEach((key, value) {
        if (value == null) return;
        filtered[key] = value.toString();
      });
    }
    AppLogger.instance.debug(
      'Built API URI',
      scope: 'apiClient',
      data: {
        'path': path,
        'queryParameters': AppLogger.instance.sanitize(queryParameters),
      },
    );
    return resolved.replace(
      queryParameters: filtered.isEmpty ? null : filtered,
    );
  }
}
