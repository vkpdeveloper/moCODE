import 'package:dio/dio.dart';

import 'api_client.dart';
import '../utils/json_parser.dart';

class FileService {
  final ApiClient _apiClient;

  FileService(this._apiClient);

  Future<List<String>> listFiles({
    required String path,
    String? directory,
  }) async {
    try {
      final response = await _apiClient.dio.get(
        '/find/file',
        queryParameters: {
          'directory': directory,
          'type': 'directory',
          'limit': 50,
          'query': path,
        },
      );
      final data = parseJsonListBytes(response.data as List<int>);
      return data.map((item) => item as String).toList();
    } on DioException {
      rethrow;
    }
  }
}
