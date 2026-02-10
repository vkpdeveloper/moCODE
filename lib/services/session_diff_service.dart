import 'package:dio/dio.dart';

import '../models/file_diff.dart';
import 'api_client.dart';
import '../utils/json_parser.dart';

class SessionDiffService {
  final ApiClient _apiClient;

  SessionDiffService(this._apiClient);

  Future<List<FileDiff>> getDiff(
    String sessionID, {
    String? directory,
    String? messageID,
  }) async {
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
