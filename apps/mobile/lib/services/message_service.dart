import 'package:dio/dio.dart';

import '../models/acp_models.dart';
import '../models/message.dart';
import '../utils/json_parser.dart';
import 'api_client.dart';
import 'event_service.dart';

class MessageService {
  final ApiClient _apiClient;
  final EventService _eventService;

  MessageService(this._apiClient, this._eventService);

  Future<AcpSessionSnapshot> getSnapshot(String sessionID) async {
    try {
      final response = await _apiClient.dio.get('/v1/sessions/$sessionID');
      final data = parseJsonObjectBytes(response.data as List<int>);
      final session = sessionFromAcpJson(
        data['session'] as Map<String, dynamic>,
      );
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
      final prompt = _partsToPrompt(parts);
      if (prompt.isEmpty) {
        throw StateError('Message must contain text or resources.');
      }
      await _eventService.promptSession(sessionID, prompt: prompt);
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
    await _eventService.promptSession(sessionID, text: text);
    return const {'accepted': true};
  }

  List<Map<String, dynamic>> _partsToPrompt(List<Map<String, dynamic>> parts) {
    final prompt = <Map<String, dynamic>>[];

    for (final part in parts) {
      final type = part['type']?.toString();
      if (type == 'text') {
        final text = part['text']?.toString().trim() ?? '';
        if (text.isEmpty) {
          continue;
        }
        prompt.add({'type': 'text', 'text': text});
        continue;
      }

      if (type == 'file') {
        final uri = part['url']?.toString().trim() ?? '';
        if (uri.isEmpty) {
          continue;
        }

        final filename = part['filename']?.toString().trim();
        final mimeType = part['mime']?.toString().trim();
        final name = (filename != null && filename.isNotEmpty)
            ? filename
            : _resourceNameFromUri(uri);

        prompt.add({
          'type': 'resource_link',
          'uri': uri,
          'name': name,
          'title': filename ?? name,
          if (mimeType != null && mimeType.isNotEmpty) 'mimeType': mimeType,
        });
      }
    }

    return prompt;
  }

  String _resourceNameFromUri(String uri) {
    if (uri.startsWith('data:')) {
      return 'attachment';
    }

    final parsed = Uri.tryParse(uri);
    final segments = parsed?.pathSegments ?? const <String>[];
    if (segments.isNotEmpty) {
      final last = segments.last.trim();
      if (last.isNotEmpty) {
        return last;
      }
    }

    return 'attachment';
  }
}
