import 'package:dio/dio.dart';

import '../models/question_request.dart';
import 'api_client.dart';

class QuestionService {
  final ApiClient _apiClient;

  QuestionService(this._apiClient);

  Future<List<QuestionRequest>> listPending({String? directory}) async {
    try {
      final response = await _apiClient.dio.get(
        '/question',
        queryParameters: {'directory': ?directory},
      );
      final data = response.data as List;
      return data
          .map((item) => QuestionRequest.fromJson(item as Map<String, dynamic>))
          .toList();
    } on DioException {
      rethrow;
    }
  }

  Future<bool> reply(
    String requestID, {
    required List<List<String>> answers,
    String? directory,
  }) async {
    try {
      await _apiClient.dio.post(
        '/question/$requestID/reply',
        data: {'answers': answers},
        queryParameters: {'directory': ?directory},
      );
      return true;
    } on DioException {
      rethrow;
    }
  }

  Future<bool> reject(String requestID, {String? directory}) async {
    try {
      await _apiClient.dio.post(
        '/question/$requestID/reject',
        queryParameters: {'directory': ?directory},
      );
      return true;
    } on DioException {
      rethrow;
    }
  }
}
