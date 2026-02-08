import 'package:dio/dio.dart';

import '../models/file_node.dart';
import 'api_client.dart';

class FileService {
  final ApiClient _apiClient;

  FileService(this._apiClient);

  Future<List<String>> listFiles({
    required String path,
    String? directory,
  }) async {
    print('directory: $directory');
    print('path: $path');
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
      print(response.data.toString());
      final data = response.data as List;
      return data.map((item) => item as String).toList();
    } on DioException catch (e) {
      print(e.response?.data.toString());
      rethrow;
    }
  }
}
