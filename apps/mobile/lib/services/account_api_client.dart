import 'package:dio/dio.dart';

import 'app_logger.dart';

class AccountApiClient {
  static const String defaultBaseUrl = 'https://mocode.ordinity.com';

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
    _dio.interceptors.add(AppLogInterceptor(clientName: 'account'));
    AppLogger.instance.info(
      'Account API client initialized',
      scope: 'accountApiClient',
      data: {'baseUrl': _baseUrl},
    );
  }

  void updateBaseUrl(String url) {
    _baseUrl = url;
    _dio.options.baseUrl = url;
    AppLogger.instance.info(
      'Account API base URL updated',
      scope: 'accountApiClient',
      data: {'baseUrl': url},
    );
  }

  String get baseUrl => _baseUrl;
  Dio get dio => _dio;
}
