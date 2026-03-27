import 'package:dio/dio.dart';

import '../models/file_diff.dart';
import '../utils/json_parser.dart';
import 'api_client.dart';

class SessionDiffService {
  SessionDiffService(this._apiClient);

  final ApiClient _apiClient;

  Future<List<FileDiff>> getDiff(
    String sessionID, {
    String? directory,
    String? messageID,
  }) async {
    try {
      final response = await _apiClient.dio.get('/v1/sessions/$sessionID/diff');
      final data = parseJsonObjectBytes(response.data as List<int>);
      return (data['diffs'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(FileDiff.fromJson)
          .toList(growable: false);
    } on DioException {
      rethrow;
    }
  }
}
