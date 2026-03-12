import 'package:dio/dio.dart';

import '../models/acp_models.dart';
import '../models/message.dart';
import '../utils/json_parser.dart';
import 'api_client.dart';

class MessageService {
  final ApiClient _apiClient;

  MessageService(this._apiClient);

  Future<AcpSessionSnapshot> getSnapshot(String sessionID) async {
    try {
      final response = await _apiClient.dio.get('/v1/sessions/$sessionID');
      final data = parseJsonObjectBytes(response.data as List<int>);
      final session = sessionFromAcpJson(data['session'] as Map<String, dynamic>);
      final entries = (data['entries'] as List<dynamic>? ?? const [])
          .map((item) => AcpSessionEntry.fromJson(item as Map<String, dynamic>))
          .toList(growable: false);
      return AcpSessionSnapshot(session: session, entries: entries);
    } on DioException {
      rethrow;
    }
  }

  Future<List<MessageWrapper>> getMessages(
    String sessionID, {
    int? limit,
    String? directory,
  }) async {
    final snapshot = await getSnapshot(sessionID);
    final messages = messageWrappersFromAcpSnapshot(snapshot);
    if (limit == null || limit >= messages.length) {
      return messages;
    }
    return messages.sublist(messages.length - limit);
  }

  Future<MessageWrapper> getMessage(
    String sessionID,
    String messageID, {
    String? directory,
  }) async {
    final messages = await getMessages(sessionID, directory: directory);
    return messages.firstWhere((message) => message.info.id == messageID);
  }

  Future<Map<String, dynamic>> sendMessage(
    String sessionID, {
    required List<Map<String, dynamic>> parts,
    String? providerID,
    String? modelID,
    String? agent,
    String? variant,
    String? directory,
  }) async {
    await sendMessageAsync(
      sessionID,
      parts: parts,
      providerID: providerID,
      modelID: modelID,
      agent: agent,
      variant: variant,
      directory: directory,
    );
    return const {'accepted': true};
  }

  Future<void> sendMessageAsync(
    String sessionID, {
    required List<Map<String, dynamic>> parts,
    String? providerID,
    String? modelID,
    String? agent,
    String? variant,
    String? directory,
  }) async {
    try {
      final text = parts
          .map((part) => part['type'] == 'text' ? part['text']?.toString() : '')
          .where((value) => value != null && value.trim().isNotEmpty)
          .cast<String>()
          .join('\n')
          .trim();
      if (text.isEmpty) {
        throw StateError('Message must contain text.');
      }
      await _apiClient.dio.post(
        '/v1/sessions/$sessionID/prompt',
        data: {'text': text},
        options: Options(receiveTimeout: Duration.zero),
      );
    } on DioException {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> sendCommand(
    String sessionID, {
    required String command,
    required String arguments,
    String? agent,
    String? model,
    String? variant,
    String? directory,
  }) async {
    final text = '/$command${arguments.trim().isEmpty ? '' : ' $arguments'}';
    await _apiClient.dio.post(
      '/v1/sessions/$sessionID/prompt',
      data: {'text': text},
      options: Options(receiveTimeout: Duration.zero),
    );
    return const {'accepted': true};
  }
}
