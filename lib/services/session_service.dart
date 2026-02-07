import 'package:dio/dio.dart';

import '../models/session.dart';
import 'api_client.dart';

class SessionService {
  final ApiClient _apiClient;

  SessionService(this._apiClient);

  Future<List<Session>> listSessions({
    String? directory,
    bool? roots,
    int? start,
    String? search,
    int? limit,
  }) async {
    try {
      final response = await _apiClient.dio.get(
        '/session',
        queryParameters: {
          'directory': ?directory,
          'roots': ?roots,
          'start': ?start,
          'search': ?search,
          'limit': ?limit,
        },
      );
      final data = response.data as List;
      return data
          .map((item) => Session.fromJson(item as Map<String, dynamic>))
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
    try {
      final response = await _apiClient.dio.post(
        '/session',
        data: {
          'parentID': ?parentID,
          'title': ?title,
        },
        queryParameters: {
          'directory': ?directory,
        },
      );
      return Session.fromJson(response.data as Map<String, dynamic>);
    } on DioException {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getSessionStatus({String? directory}) async {
    try {
      final response = await _apiClient.dio.get(
        '/session/status',
        queryParameters: {
          'directory': ?directory,
        },
      );
      return response.data as Map<String, dynamic>;
    } on DioException {
      rethrow;
    }
  }

  Future<Session> getSession(String sessionID, {String? directory}) async {
    try {
      final response = await _apiClient.dio.get(
        '/session/$sessionID',
        queryParameters: {
          'directory': ?directory,
        },
      );
      return Session.fromJson(response.data as Map<String, dynamic>);
    } on DioException {
      rethrow;
    }
  }

  Future<bool> deleteSession(String sessionID, {String? directory}) async {
    try {
      await _apiClient.dio.delete(
        '/session/$sessionID',
        queryParameters: {
          'directory': ?directory,
        },
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
    try {
      final response = await _apiClient.dio.patch(
        '/session/$sessionID',
        data: {
          'title': ?title,
          'archived': ?archived,
        },
        queryParameters: {
          'directory': ?directory,
        },
      );
      return Session.fromJson(response.data as Map<String, dynamic>);
    } on DioException {
      rethrow;
    }
  }

  Future<List<Session>> getSessionChildren(
    String sessionID, {
    String? directory,
  }) async {
    try {
      final response = await _apiClient.dio.get(
        '/session/$sessionID/children',
        queryParameters: {
          'directory': ?directory,
        },
      );
      final data = response.data as List;
      return data
          .map((item) => Session.fromJson(item as Map<String, dynamic>))
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
    try {
      final response = await _apiClient.dio.post(
        '/session/$sessionID/fork',
        data: {
          'messageID': ?messageID,
        },
        queryParameters: {
          'directory': ?directory,
        },
      );
      return Session.fromJson(response.data as Map<String, dynamic>);
    } on DioException {
      rethrow;
    }
  }

  Future<bool> abortSession(String sessionID, {String? directory}) async {
    try {
      await _apiClient.dio.post(
        '/session/$sessionID/abort',
        queryParameters: {
          'directory': ?directory,
        },
      );
      return true;
    } on DioException {
      rethrow;
    }
  }

  Future<Session> shareSession(String sessionID, {String? directory}) async {
    try {
      final response = await _apiClient.dio.post(
        '/session/$sessionID/share',
        queryParameters: {
          'directory': ?directory,
        },
      );
      return Session.fromJson(response.data as Map<String, dynamic>);
    } on DioException {
      rethrow;
    }
  }

  Future<Session> unshareSession(String sessionID, {String? directory}) async {
    try {
      final response = await _apiClient.dio.delete(
        '/session/$sessionID/share',
        queryParameters: {
          'directory': ?directory,
        },
      );
      return Session.fromJson(response.data as Map<String, dynamic>);
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
    try {
      await _apiClient.dio.post(
        '/session/$sessionID/summarize',
        data: {
          'providerID': providerID,
          'modelID': modelID,
          'auto': ?auto_,
        },
        queryParameters: {
          'directory': ?directory,
        },
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
    try {
      final response = await _apiClient.dio.post(
        '/session/$sessionID/revert',
        data: {
          'messageID': messageID,
          'partID': ?partID,
        },
        queryParameters: {
          'directory': ?directory,
        },
      );
      return Session.fromJson(response.data as Map<String, dynamic>);
    } on DioException {
      rethrow;
    }
  }

  Future<Session> unrevertSession(
    String sessionID, {
    String? directory,
  }) async {
    try {
      final response = await _apiClient.dio.post(
        '/session/$sessionID/unrevert',
        queryParameters: {
          'directory': ?directory,
        },
      );
      return Session.fromJson(response.data as Map<String, dynamic>);
    } on DioException {
      rethrow;
    }
  }
}
