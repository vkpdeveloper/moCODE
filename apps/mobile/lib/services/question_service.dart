import 'package:dio/dio.dart';

import '../models/question_request.dart';
import '../utils/json_parser.dart';
import 'api_client.dart';
import 'event_service.dart';

class QuestionService {
  QuestionService(this._apiClient, this._eventService);

  final ApiClient _apiClient;
  final EventService _eventService;

  Future<List<QuestionRequest>> listPending({required String sessionID}) async {
    try {
      final response = await _apiClient.dio.get(
        '/v1/sessions/$sessionID/questions',
      );
      final data = parseJsonObjectBytes(response.data as List<int>);
      return (data['questions'] as List<dynamic>? ?? const [])
          .map((item) {
            final record = item as Map<String, dynamic>;
            final request =
                (record['request'] as Map?)?.cast<String, dynamic>() ??
                const <String, dynamic>{};
            return QuestionRequest.fromJson({
              ...request,
              'id': record['requestId'] as String? ?? '',
              'sessionID': record['sessionId'] as String? ?? sessionID,
            });
          })
          .toList(growable: false);
    } on DioException {
      rethrow;
    }
  }

  Future<bool> reply(
    QuestionRequest request, {
    required List<List<String>> answers,
  }) async {
    try {
      final mappedAnswers = <String, List<String>>{};
      for (var index = 0; index < request.questions.length; index += 1) {
        final question = request.questions[index];
        final response = index < answers.length
            ? answers[index]
            : const <String>[];
        mappedAnswers[question.id] = List<String>.from(response);
      }
      await _eventService.replyQuestion(
        request.sessionID,
        request.id,
        outcome: {'outcome': 'answered', 'answers': mappedAnswers},
      );
      return true;
    } on DioException {
      rethrow;
    }
  }

  Future<bool> reject(QuestionRequest request) async {
    try {
      await _eventService.replyQuestion(
        request.sessionID,
        request.id,
        outcome: const {'outcome': 'cancelled'},
      );
      return true;
    } on DioException {
      rethrow;
    }
  }
}
