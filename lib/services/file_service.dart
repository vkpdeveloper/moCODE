import 'package:dio/dio.dart';

import '../models/file_node.dart';
import 'api_client.dart';
import '../utils/json_parser.dart';

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
      final data = parseJsonListBytes(response.data as List<int>);
      return data.map((item) => item as String).toList();
    } on DioException catch (e) {
      if (e.response?.data is List<int>) {
        print(String.fromCharCodes(e.response!.data as List<int>));
      } else {
        print(e.response?.data.toString());
      }
      rethrow;
    }
  }
}
