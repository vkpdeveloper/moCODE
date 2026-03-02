import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/message.dart';
import '../models/server_type.dart';
import '../utils/app_logger.dart';
import '../utils/json_parser.dart';
import 'api_client.dart';
import 'codex_app_server_service.dart';

class MessageService {
  final ApiClient _apiClient;
  final ServerType _serverType;
  final CodexAppServerService? _codex;

  MessageService(
    this._apiClient, {
    ServerType serverType = ServerType.openCode,
    CodexAppServerService? codex,
  }) : _serverType = serverType,
       _codex = codex;

  bool get _useCodex => _serverType == ServerType.codex;

  Future<List<MessageWrapper>> getMessages(
    String sessionID, {
    int? limit,
    String? directory,
  }) async {
    if (_useCodex) {
      AppLogger.debug(
        'service.message',
        'getMessages:codex',
        data: {'sessionId': sessionID},
      );
      return (_codex ?? (throw StateError('Codex service missing')))
          .getMessages(sessionID, workspace: directory);
    }

    try {
      final response = await _apiClient.dio.get(
        '/session/$sessionID/message',
        queryParameters: {'limit': limit, 'directory': directory},
      );
      final data = parseJsonListBytes(response.data as List<int>);
      debugPrint(response.requestOptions.uri.toString());
      return data
          .map((item) => MessageWrapper.fromJson(item as Map<String, dynamic>))
          .toList();
    } on DioException {
      rethrow;
    }
  }

  Future<MessageWrapper> getMessage(
    String sessionID,
    String messageID, {
    String? directory,
  }) async {
    if (_useCodex) {
      final messages = await getMessages(sessionID, directory: directory);
      return messages.firstWhere((m) => m.info.id == messageID);
    }

    try {
      final response = await _apiClient.dio.get(
        '/session/$sessionID/message/$messageID',
        queryParameters: {'directory': ?directory},
      );
      final data = parseJsonObjectBytes(response.data as List<int>);
      return MessageWrapper.fromJson(data);
    } on DioException {
      rethrow;
    }
  }

  Map<String, dynamic> _buildMessageData({
    required List<Map<String, dynamic>> parts,
    String? providerID,
    String? modelID,
    String? agent,
    String? variant,
  }) {
    final data = <String, dynamic>{'parts': parts};
    if (providerID != null && modelID != null) {
      data['model'] = {'providerID': providerID, 'modelID': modelID};
    }
    if (agent != null) data['agent'] = agent;
    if (variant != null) data['variant'] = variant;
    return data;
  }

  String _extractText(List<Map<String, dynamic>> parts) {
    final chunks = <String>[];
    for (final part in parts) {
      if (part['type']?.toString() == 'text') {
        final text = part['text']?.toString();
        if (text != null && text.isNotEmpty) chunks.add(text);
      }
    }
    return chunks.join('\n');
  }

  String? _codexModel(String? modelID) {
    if (modelID == null || modelID.isEmpty) return null;
    // Codex app-server expects bare model ids (for example "gpt-5.3-codex"),
    // not provider-prefixed paths.
    if (modelID.contains('/')) {
      final parts = modelID.split('/');
      if (parts.length > 1) {
        return parts.sublist(1).join('/');
      }
    }
    return modelID;
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
    if (_useCodex) {
      AppLogger.info(
        'service.message',
        'sendMessage:codex',
        data: {
          'sessionId': sessionID,
          'providerID': providerID,
          'modelID': modelID,
          'parts': parts.length,
        },
      );
      await (_codex ?? (throw StateError('Codex service missing'))).startTurn(
        threadId: sessionID,
        text: _extractText(parts),
        workspace: directory,
        model: _codexModel(modelID),
      );
      return <String, dynamic>{'ok': true};
    }

    try {
      final response = await _apiClient.dio.post(
        '/session/$sessionID/message',
        data: _buildMessageData(
          parts: parts,
          providerID: providerID,
          modelID: modelID,
          agent: agent,
          variant: variant,
        ),
        queryParameters: {'directory': ?directory},
        options: Options(receiveTimeout: Duration.zero),
      );
      return parseJsonObjectBytes(response.data as List<int>);
    } on DioException {
      rethrow;
    }
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
    if (_useCodex) {
      await sendMessage(
        sessionID,
        parts: parts,
        providerID: providerID,
        modelID: modelID,
        agent: agent,
        variant: variant,
        directory: directory,
      );
      return;
    }

    try {
      await _apiClient.dio.post(
        '/session/$sessionID/prompt_async',
        data: _buildMessageData(
          parts: parts,
          providerID: providerID,
          modelID: modelID,
          agent: agent,
          variant: variant,
        ),
        queryParameters: {'directory': ?directory},
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
    if (_useCodex) {
      throw UnsupportedError('Commands are not supported on Codex MVP');
    }

    try {
      final response = await _apiClient.dio.post(
        '/session/$sessionID/command',
        data: {
          'command': command,
          'arguments': arguments,
          'agent': ?agent,
          'model': ?model,
          'variant': ?variant,
        },
        queryParameters: {'directory': ?directory},
        options: Options(receiveTimeout: Duration.zero),
      );
      return parseJsonObjectBytes(response.data as List<int>);
    } on DioException {
      rethrow;
    }
  }
}
