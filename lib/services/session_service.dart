import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/server_type.dart';
import '../models/session.dart';
import '../utils/json_parser.dart';
import '../utils/app_logger.dart';
import 'api_client.dart';
import 'codex_app_server_service.dart';

class SessionService {
  final ApiClient _apiClient;
  final ServerType _serverType;
  final CodexAppServerService? _codex;

  SessionService(
    this._apiClient, {
    ServerType serverType = ServerType.openCode,
    CodexAppServerService? codex,
  }) : _serverType = serverType,
       _codex = codex;

  bool get _useCodex => _serverType == ServerType.codex;

  Future<List<Session>> listSessions({
    String? directory,
    bool roots = true,
    int? start,
    String? search,
    int limit = 55,
  }) async {
    if (_useCodex) {
      AppLogger.debug(
        'service.session',
        'listSessions:codex',
        data: {'workspace': directory},
      );
      return (_codex ?? (throw StateError('Codex service missing')))
          .listSessions(workspace: directory);
    }

    try {
      final response = await _apiClient.dio.get(
        '/session',
        queryParameters: {
          'directory': directory,
          'roots': roots,
          'start': start,
          'search': search,
          'limit': limit,
        },
      );
      final data = parseJsonListBytes(response.data as List<int>);
      debugPrint('[SessionService] Received ${data.length} sessions');
      return data
          .map((item) {
            try {
              return Session.fromJson(item as Map<String, dynamic>);
            } catch (e) {
              debugPrint(
                '[SessionService] Failed to parse session: $e\nRaw: $item',
              );
              return null;
            }
          })
          .whereType<Session>()
          .toList();
    } on DioException {
      rethrow;
    }
  }

  Future<Session> createSession({
    String? parentID,
    String? title,
    String? directory,
  }) async {
    if (_useCodex) {
      AppLogger.debug(
        'service.session',
        'createSession:codex',
        data: {'workspace': directory},
      );
      return (_codex ?? (throw StateError('Codex service missing')))
          .createSession(workspace: directory);
    }

    try {
      final payload = <String, dynamic>{};
      if (parentID != null) payload['parentID'] = parentID;
      if (title != null) payload['title'] = title;

      final response = await _apiClient.dio.post(
        '/session',
        data: payload,
        queryParameters: {'directory': directory},
      );
      final parsed = parseJsonObjectBytes(response.data as List<int>);
      return Session.fromJson(parsed);
    } on DioException {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getSessionStatus({String? directory}) async {
    if (_useCodex) {
      final sessions = await listSessions(directory: directory);
      final map = <String, dynamic>{};
      for (final s in sessions) {
        map[s.id] = {'type': 'idle'};
      }
      return map;
    }

    try {
      final response = await _apiClient.dio.get(
        '/session/status',
        queryParameters: {'directory': directory},
      );
      return parseJsonObjectBytes(response.data as List<int>);
    } on DioException {
      rethrow;
    }
  }

  Future<Session> getSession(String sessionID, {String? directory}) async {
    if (_useCodex) {
      AppLogger.debug(
        'service.session',
        'getSession:codex',
        data: {'sessionId': sessionID},
      );
      return (_codex ?? (throw StateError('Codex service missing'))).getSession(
        sessionID,
      );
    }

    try {
      final response = await _apiClient.dio.get(
        '/session/$sessionID',
        queryParameters: {'directory': directory},
      );
      final data = parseJsonObjectBytes(response.data as List<int>);
      return Session.fromJson(data);
    } on DioException {
      rethrow;
    }
  }

  Future<bool> deleteSession(String sessionID, {String? directory}) async {
    if (_useCodex) {
      await (_codex ?? (throw StateError('Codex service missing')))
          .archiveThread(sessionID);
      return true;
    }

    try {
      await _apiClient.dio.delete(
        '/session/$sessionID',
        queryParameters: {'directory': directory},
      );
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
    if (_useCodex) {
      if (title != null && title.isNotEmpty) {
        await (_codex ?? (throw StateError('Codex service missing')))
            .setThreadName(sessionID, title);
      }
      if (archived != null) {
        if (archived == 1) {
          await (_codex ?? (throw StateError('Codex service missing')))
              .archiveThread(sessionID);
        } else {
          await (_codex ?? (throw StateError('Codex service missing')))
              .unarchiveThread(sessionID);
        }
      }
      return getSession(sessionID, directory: directory);
    }

    try {
      final response = await _apiClient.dio.patch(
        '/session/$sessionID',
        data: {'title': title, 'archived': archived},
        queryParameters: {'directory': directory},
      );
      final data = parseJsonObjectBytes(response.data as List<int>);
      return Session.fromJson(data);
    } on DioException {
      rethrow;
    }
  }

  Future<List<Session>> getSessionChildren(
    String sessionID, {
    String? directory,
  }) async {
    if (_useCodex) return const [];

    try {
      final response = await _apiClient.dio.get(
        '/session/$sessionID/children',
        queryParameters: {'directory': directory},
      );
      final data = parseJsonListBytes(response.data as List<int>);
      return data
          .map((item) {
            try {
              return Session.fromJson(item as Map<String, dynamic>);
            } catch (e) {
              debugPrint(
                '[SessionService] Failed to parse child session: $e\nRaw: $item',
              );
              return null;
            }
          })
          .whereType<Session>()
          .toList();
    } on DioException {
      rethrow;
    }
  }

  Future<Session> forkSession(
    String sessionID, {
    String? messageID,
    String? directory,
  }) async {
    if (_useCodex) {
      return (_codex ?? (throw StateError('Codex service missing'))).forkThread(
        sessionID,
      );
    }

    try {
      final response = await _apiClient.dio.post(
        '/session/$sessionID/fork',
        data: {'messageID': ?messageID},
        queryParameters: {'directory': ?directory},
      );
      final data = parseJsonObjectBytes(response.data as List<int>);
      return Session.fromJson(data);
    } on DioException {
      rethrow;
    }
  }

  Future<bool> abortSession(String sessionID, {String? directory}) async {
    if (_useCodex) {
      await (_codex ?? (throw StateError('Codex service missing')))
          .interruptTurn(sessionID);
      return true;
    }

    try {
      await _apiClient.dio.post(
        '/session/$sessionID/abort',
        queryParameters: {'directory': ?directory},
      );
      return true;
    } on DioException {
      rethrow;
    }
  }

  Future<Session> shareSession(String sessionID, {String? directory}) async {
    if (_useCodex) {
      return getSession(sessionID, directory: directory);
    }
    try {
      final response = await _apiClient.dio.post(
        '/session/$sessionID/share',
        queryParameters: {'directory': ?directory},
      );
      final data = parseJsonObjectBytes(response.data as List<int>);
      return Session.fromJson(data);
    } on DioException {
      rethrow;
    }
  }

  Future<Session> unshareSession(String sessionID, {String? directory}) async {
    if (_useCodex) {
      return getSession(sessionID, directory: directory);
    }

    try {
      final response = await _apiClient.dio.delete(
        '/session/$sessionID/share',
        queryParameters: {'directory': ?directory},
      );
      final data = parseJsonObjectBytes(response.data as List<int>);
      return Session.fromJson(data);
    } on DioException {
      rethrow;
    }
  }

  Future<bool> summarizeSession(
    String sessionID, {
    required String providerID,
    required String modelID,
    bool? auto_,
    String? directory,
  }) async {
    if (_useCodex) return false;

    try {
      await _apiClient.dio.post(
        '/session/$sessionID/summarize',
        data: {'providerID': providerID, 'modelID': modelID, 'auto': ?auto_},
        queryParameters: {'directory': ?directory},
      );
      return true;
    } on DioException {
      rethrow;
    }
  }

  Future<Session> revertSession(
    String sessionID, {
    required String messageID,
    String? partID,
    String? directory,
  }) async {
    if (_useCodex) {
      await (_codex ?? (throw StateError('Codex service missing')))
          .rollbackThread(sessionID);
      return getSession(sessionID, directory: directory);
    }

    try {
      final response = await _apiClient.dio.post(
        '/session/$sessionID/revert',
        data: {'messageID': messageID, 'partID': ?partID},
        queryParameters: {'directory': ?directory},
      );
      final data = parseJsonObjectBytes(response.data as List<int>);
      return Session.fromJson(data);
    } on DioException {
      rethrow;
    }
  }

  Future<Session> unrevertSession(String sessionID, {String? directory}) async {
    if (_useCodex) {
      return getSession(sessionID, directory: directory);
    }

    try {
      final response = await _apiClient.dio.post(
        '/session/$sessionID/unrevert',
        queryParameters: {'directory': ?directory},
      );
      final data = parseJsonObjectBytes(response.data as List<int>);
      return Session.fromJson(data);
    } on DioException {
      rethrow;
    }
  }
}
