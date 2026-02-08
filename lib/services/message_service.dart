import 'package:dio/dio.dart';

import 'package:flutter/foundation.dart';

import '../models/message.dart';
import 'api_client.dart';

List<MessageWrapper> _parseMessages(List<dynamic> data) {
  return data
      .map((item) => MessageWrapper.fromJson(item as Map<String, dynamic>))
      .toList();
}

class MessageService {
  final ApiClient _apiClient;

  MessageService(this._apiClient);

  Future<List<MessageWrapper>> getMessages(
    String sessionID, {
    int? limit,
    String? directory,
  }) async {
    try {
      final response = await _apiClient.dio.get(
        '/session/$sessionID/message',
        queryParameters: {'limit': limit, 'directory': directory},
      );
      final data = response.data as List;
      return compute(_parseMessages, data);
    } on DioException {
      rethrow;
    }
  }

  Future<MessageWrapper> getMessage(
    String sessionID,
    String messageID, {
    String? directory,
  }) async {
    try {
      final response = await _apiClient.dio.get(
        '/session/$sessionID/message/$messageID',
        queryParameters: {'directory': ?directory},
      );
      return MessageWrapper.fromJson(response.data as Map<String, dynamic>);
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

  Future<Map<String, dynamic>> sendMessage(
    String sessionID, {
    required List<Map<String, dynamic>> parts,
    String? providerID,
    String? modelID,
    String? agent,
    String? variant,
    String? directory,
  }) async {
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
      return response.data as Map<String, dynamic>;
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
      return response.data as Map<String, dynamic>;
    } on DioException {
      rethrow;
    }
  }
}
