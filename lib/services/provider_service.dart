import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

import '../models/provider.dart';
import 'api_client.dart';

class ProviderService {
  final ApiClient _apiClient;

  ProviderService(this._apiClient);

  Future<ProviderListResponse> listProviders({String? directory}) async {
    try {
      final response = await _apiClient.dio.get(
        '/provider',
        queryParameters: {
          'directory': ?directory,
        },
      );
      final data = response.data as Map<String, dynamic>;
      debugPrint('[ProviderService] default: ${data['default']}');
      debugPrint('[ProviderService] connected: ${data['connected']}');
      return ProviderListResponse.fromJson(data);
    } on DioException {
      rethrow;
    }
  }
}
