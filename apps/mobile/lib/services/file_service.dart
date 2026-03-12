import 'package:dio/dio.dart';

import 'api_client.dart';
import '../models/file_node.dart';
import '../utils/json_parser.dart';

class FileService {
  final ApiClient _apiClient;

  FileService(this._apiClient);

  Future<List<FileNode>> listDirectory({
    required String path,
    String? directory,
  }) async {
    try {
      final response = await _apiClient.dio.get(
        '/v1/files',
        queryParameters: {'directory': directory, 'path': path},
      );
      final data = parseJsonListBytes(response.data as List<int>);
      return data
          .map((item) => FileNode.fromJson(item as Map<String, dynamic>))
          .toList();
    } on DioException {
      rethrow;
    }
  }

  Future<List<String>> searchDirectories({
    required String query,
    String? directory,
    int limit = 200,
  }) async {
    try {
      final response = await _apiClient.dio.get(
        '/v1/files/search',
        queryParameters: {
          'directory': directory,
          'type': 'directory',
          'limit': limit,
          'query': query,
        },
      );
      final data = parseJsonListBytes(response.data as List<int>);
      return data.map((item) => item as String).toList();
    } on DioException {
      rethrow;
    }
  }

  Future<List<String>> listFiles({
    required String path,
    String? directory,
  }) async {
    return searchDirectories(query: path, directory: directory, limit: 50);
  }
}
