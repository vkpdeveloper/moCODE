import 'package:dio/dio.dart';

import '../models/server_type.dart';
import '../models/todo.dart';
import 'api_client.dart';
import '../utils/json_parser.dart';

class TodoService {
  final ApiClient _apiClient;
  final ServerType _serverType;

  TodoService(this._apiClient, {ServerType serverType = ServerType.openCode})
    : _serverType = serverType;

  Future<List<Todo>> getTodos(String sessionID, {String? directory}) async {
    if (_serverType == ServerType.codex) return const [];

    try {
      final response = await _apiClient.dio.get(
        '/session/$sessionID/todo',
        queryParameters: {'directory': ?directory},
      );
      final data = parseJsonListBytes(response.data as List<int>);
      return data
          .map((item) => Todo.fromJson(item as Map<String, dynamic>))
          .toList();
    } on DioException {
      rethrow;
    }
  }
}
