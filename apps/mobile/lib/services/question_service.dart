import '../models/question_request.dart';

class QuestionService {
  Future<List<QuestionRequest>> listPending({String? directory}) async {
    return const [];
  }

  Future<bool> reply(
    String requestID, {
    required List<List<String>> answers,
    String? directory,
  }) async {
    return false;
  }

  Future<bool> reject(String requestID, {String? directory}) async {
    return false;
  }
}
