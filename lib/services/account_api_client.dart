import 'package:dio/dio.dart';

class AccountApiClient {
  static const String defaultBaseUrl = 'https://mo-code.vercel.app';

  late Dio _dio;
  String _baseUrl;

  AccountApiClient({String baseUrl = defaultBaseUrl}) : _baseUrl = baseUrl {
    _dio = Dio(
      BaseOptions(
        baseUrl: _baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(minutes: 3),
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
}
