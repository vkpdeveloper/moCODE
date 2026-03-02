import 'package:dio/dio.dart';

import '../models/file_diff.dart';
import '../models/server_type.dart';
import 'api_client.dart';
import '../utils/json_parser.dart';

class SessionDiffService {
  final ApiClient _apiClient;
  final ServerType _serverType;

  SessionDiffService(
    this._apiClient, {
    ServerType serverType = ServerType.openCode,
  }) : _serverType = serverType;

  Future<List<FileDiff>> getDiff(
    String sessionID, {
    String? directory,
    String? messageID,
  }) async {
    if (_serverType == ServerType.codex) return const [];

    try {
      final response = await _apiClient.dio.get(
        '/session/$sessionID/diff',
        queryParameters: {'directory': ?directory, 'messageID': ?messageID},
      );
      final data = parseJsonListBytes(response.data as List<int>);
      return data
          .map((item) => FileDiff.fromJson(item as Map<String, dynamic>))
          .toList();
    } on DioException {
      rethrow;
    }
  }
}
