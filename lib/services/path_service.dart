import 'package:dio/dio.dart';

import '../models/path_info.dart';
import 'api_client.dart';

class PathService {
  final ApiClient _apiClient;

  PathService(this._apiClient);

  Future<PathInfo> getPaths({String? directory}) async {
    try {
      final response = await _apiClient.dio.get(
        '/path',
        queryParameters: {'directory': directory},
      );
      return PathInfo.fromJson(response.data as Map<String, dynamic>);
    } on DioException {
      rethrow;
    }
  }
}
