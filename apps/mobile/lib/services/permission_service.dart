import 'package:dio/dio.dart';

import '../models/acp_models.dart';
import '../models/permission_request.dart';
import '../utils/json_parser.dart';
import 'api_client.dart';
import 'event_service.dart';

class PermissionService {
  PermissionService(this._apiClient, this._eventService);

  final ApiClient _apiClient;
  final EventService _eventService;

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
      await _eventService.replyPermission(
        sessionID,
        requestID,
        outcome: switch (reply) {
          'always' => const {'outcome': 'selected', 'optionId': 'allow_always'},
          'reject' => const {'outcome': 'selected', 'optionId': 'reject_once'},
          _ => const {'outcome': 'selected', 'optionId': 'allow_once'},
        },
      );
      return true;
    } on DioException {
      rethrow;
    }
  }
}
