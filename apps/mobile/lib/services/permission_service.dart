import 'package:dio/dio.dart';

import '../models/acp_models.dart';
import '../models/permission_request.dart';
import '../utils/json_parser.dart';
import 'api_client.dart';

class PermissionService {
  final ApiClient _apiClient;

  PermissionService(this._apiClient);

  Future<List<PermissionRequest>> listPending({
    required String sessionID,
  }) async {
    try {
      final response = await _apiClient.dio.get(
        '/v1/sessions/$sessionID/permissions',
      );
      final data = parseJsonObjectBytes(response.data as List<int>);
      final permissions = (data['permissions'] as List<dynamic>? ?? const [])
          .map((item) {
            final record = item as Map<String, dynamic>;
            return permissionRequestFromAcp(
              requestId: record['requestId'] as String? ?? '',
              sessionId: record['sessionId'] as String? ?? sessionID,
              request:
                  (record['request'] as Map?)?.cast<String, dynamic>() ??
                  const <String, dynamic>{},
            );
          })
          .toList(growable: false);
      return permissions;
    } on DioException {
      rethrow;
    }
  }

  Future<bool> reply(
    String sessionID,
    String requestID, {
    required String reply,
  }) async {
    try {
      await _apiClient.dio.post(
        '/v1/sessions/$sessionID/permissions/$requestID/reply',
        data: {'reply': reply},
      );
      return true;
    } on DioException {
      rethrow;
    }
  }
}
