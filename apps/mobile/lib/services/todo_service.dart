import 'package:dio/dio.dart';

import '../models/todo.dart';
import '../utils/json_parser.dart';
import 'api_client.dart';

class TodoService {
  TodoService(this._apiClient);

  final ApiClient _apiClient;

  Future<List<Todo>> getTodos(String sessionID, {String? directory}) async {
    try {
      final response = await _apiClient.dio.get(
        '/v1/sessions/$sessionID/todos',
      );
      final data = parseJsonObjectBytes(response.data as List<int>);
      return (data['todos'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(Todo.fromJson)
          .toList(growable: false);
    } on DioException {
      rethrow;
    }
  }
}
