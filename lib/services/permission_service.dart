import 'package:dio/dio.dart';

import '../models/permission_request.dart';
import 'api_client.dart';
import '../utils/json_parser.dart';

class PermissionService {
  final ApiClient _apiClient;

  PermissionService(this._apiClient);

  Future<List<PermissionRequest>> listPending({String? directory}) async {
    try {
      final response = await _apiClient.dio.get(
        '/permission',
        queryParameters: {'directory': ?directory},
      );
      final data = parseJsonListBytes(response.data as List<int>);
      return data
          .map(
            (item) => PermissionRequest.fromJson(item as Map<String, dynamic>),
          )
          .toList();
    } on DioException {
      rethrow;
    }
  }

  Future<bool> reply(
    String requestID, {
    required String reply,
    String? directory,
  }) async {
    try {
      await _apiClient.dio.post(
        '/permission/$requestID/reply',
        data: {'reply': reply},
        queryParameters: {'directory': ?directory},
      );
      return true;
    } on DioException {
      rethrow;
    }
  }
}
