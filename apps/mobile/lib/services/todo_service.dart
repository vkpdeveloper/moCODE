import 'package:dio/dio.dart';

import '../models/todo.dart';
import 'api_client.dart';
import '../utils/json_parser.dart';

class TodoService {
  final ApiClient _apiClient;

  TodoService(this._apiClient);

  Future<List<Todo>> getTodos(String sessionID, {String? directory}) async {
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
