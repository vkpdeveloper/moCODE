import 'package:dio/dio.dart';

import 'background_transformer.dart' as custom;

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
      ),
    );
    _dio.transformer = custom.BackgroundTransformer();
  }

  void updateBaseUrl(String url) {
    _baseUrl = url;
    _dio.options.baseUrl = url;
  }

  String get baseUrl => _baseUrl;
  Dio get dio => _dio;
}
