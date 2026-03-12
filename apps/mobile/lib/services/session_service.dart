import 'package:dio/dio.dart';

import '../models/acp_models.dart';
import '../models/session.dart';
import '../utils/json_parser.dart';
import 'api_client.dart';
import 'app_logger.dart';

class SessionService {
  final ApiClient _apiClient;

  SessionService(this._apiClient);

  Future<List<Session>> listSessions({
    String? directory,
    String? projectID,
    bool roots = true,
    int? start,
    String? search,
    int limit = 55,
  }) async {
    try {
      final response = await _apiClient.dio.get(
        '/v1/sessions',
        queryParameters: {
          'projectId': projectID,
        },
      );
      final data = parseJsonObjectBytes(response.data as List<int>);
      final sessions = (data['sessions'] as List<dynamic>? ?? const [])
          .map((item) {
            try {
              return sessionFromAcpJson(item as Map<String, dynamic>);
            } catch (e) {
              AppLogger.instance.error(
                'Failed to parse session payload',
                scope: 'sessionService',
                data: {'raw': item},
                error: e,
              );
              return null;
            }
          })
          .whereType<Session>()
          .toList();
      if (directory == null || directory.isEmpty) {
        return sessions;
      }
      return sessions.where((session) => session.directory == directory).toList();
    } on DioException {
      rethrow;
    }
  }

  Future<Session> createSession({
    String? parentID,
    String? title,
    String? agentID,
    String? directory,
    String? projectID,
  }) async {
    try {
      var resolvedProjectId = projectID;
      if ((resolvedProjectId == null || resolvedProjectId.isEmpty) &&
          directory != null &&
          directory.isNotEmpty) {
        final openResponse = await _apiClient.dio.post(
          '/v1/projects/open',
          data: {'path': directory},
        );
        final openData = parseJsonObjectBytes(openResponse.data as List<int>);
        resolvedProjectId =
            (openData['project'] as Map<String, dynamic>)['id'] as String?;
      }

      if (resolvedProjectId == null || resolvedProjectId.isEmpty) {
        throw StateError('Project is required to create a session.');
      }
      if (agentID == null || agentID.isEmpty) {
        throw StateError('Agent is required to create a session.');
      }

      final response = await _apiClient.dio.post(
        '/v1/sessions',
        data: {
          'projectId': resolvedProjectId,
          'agentId': agentID,
        },
      );
      final data = parseJsonObjectBytes(response.data as List<int>);
      final session = sessionFromAcpJson(data['session'] as Map<String, dynamic>);
      if (title != null && title.trim().isNotEmpty) {
        return updateSession(session.id, title: title);
      }
      return session;
    } on DioException {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getSessionStatus({String? directory}) async {
    final sessions = await listSessions(directory: directory, limit: 200);
    return {
      for (final session in sessions)
        session.id: {
          'type': sessionFromStatus(session),
        },
    };
  }

  Future<Session> getSession(String sessionID, {String? directory}) async {
    try {
      final response = await _apiClient.dio.get('/v1/sessions/$sessionID');
      final data = parseJsonObjectBytes(response.data as List<int>);
      return sessionFromAcpJson(data['session'] as Map<String, dynamic>);
    } on DioException {
      rethrow;
    }
  }

  Future<bool> deleteSession(String sessionID, {String? directory}) async {
    try {
      await _apiClient.dio.delete('/v1/sessions/$sessionID');
      return true;
    } on DioException {
      rethrow;
    }
  }

  Future<Session> updateSession(
    String sessionID, {
    String? title,
    int? archived,
    String? directory,
  }) async {
    try {
      final response = await _apiClient.dio.patch(
        '/v1/sessions/$sessionID',
        data: {'title': title},
      );
      final data = parseJsonObjectBytes(response.data as List<int>);
      return sessionFromAcpJson(data['session'] as Map<String, dynamic>);
    } on DioException {
      rethrow;
    }
  }

  Future<List<Session>> getSessionChildren(
    String sessionID, {
    String? directory,
  }) async {
    return const [];
  }

  Future<Session> forkSession(
    String sessionID, {
    String? messageID,
    String? directory,
  }) async {
    final existing = await getSession(sessionID, directory: directory);
    return createSession(
      agentID: existing.agentID,
      projectID: existing.projectID,
      directory: existing.directory,
    );
  }

  Future<bool> abortSession(String sessionID, {String? directory}) async {
    try {
      await _apiClient.dio.post('/v1/sessions/$sessionID/cancel');
      return true;
    } on DioException {
      rethrow;
    }
  }

  Future<Session> shareSession(String sessionID, {String? directory}) async {
    throw StateError('Session sharing is not available for ACP sessions yet.');
  }

  Future<Session> unshareSession(String sessionID, {String? directory}) async {
    throw StateError('Session sharing is not available for ACP sessions yet.');
  }

  Future<bool> summarizeSession(
    String sessionID, {
    required String providerID,
    required String modelID,
    bool? auto_,
    String? directory,
  }) async {
    return false;
  }

  Future<Session> revertSession(
    String sessionID, {
    required String messageID,
    String? partID,
    String? directory,
  }) async {
    throw StateError('Undo is not available for ACP sessions yet.');
  }

  Future<Session> unrevertSession(String sessionID, {String? directory}) async {
    throw StateError('Redo is not available for ACP sessions yet.');
  }
}

String sessionFromStatus(Session session) {
  final value = session.status?.trim();
  if (value == null || value.isEmpty || value == 'idle') {
    return 'idle';
  }
  return 'busy';
}
