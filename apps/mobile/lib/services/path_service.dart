import 'package:dio/dio.dart';

import '../models/path_info.dart';
import 'api_client.dart';
import '../utils/json_parser.dart';

class PathService {
  final ApiClient _apiClient;

  PathService(this._apiClient);

  Future<PathInfo> getPaths({String? directory}) async {
    try {
      final response = await _apiClient.dio.get(
        '/v1/path',
        queryParameters: {'directory': directory},
      );
      final data = parseJsonObjectBytes(response.data as List<int>);
      return PathInfo.fromJson(data);
    } on DioException {
      rethrow;
    }
  }
}
