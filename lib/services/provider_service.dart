import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

import '../models/provider.dart';
import '../models/server_type.dart';
import '../utils/app_logger.dart';
import '../utils/json_parser.dart';
import 'api_client.dart';
import 'codex_app_server_service.dart';

class ProviderService {
  final ApiClient _apiClient;
  final ServerType _serverType;
  final CodexAppServerService? _codex;

  ProviderService(
    this._apiClient, {
    ServerType serverType = ServerType.openCode,
    CodexAppServerService? codex,
  }) : _serverType = serverType,
       _codex = codex;

  bool get _useCodex => _serverType == ServerType.codex;

  Future<ProviderListResponse> listProviders({String? directory}) async {
    if (_useCodex) {
      AppLogger.debug('service.model', 'listProviders:codex');
      return (_codex ?? (throw StateError('Codex service missing'))).listModels();
    }

    try {
      final response = await _apiClient.dio.get(
        '/provider',
        queryParameters: {'directory': ?directory},
      );
      final data = parseJsonObjectBytes(response.data as List<int>);
      debugPrint('[ProviderService] default: ${data['default']}');
      debugPrint('[ProviderService] connected: ${data['connected']}');
      return ProviderListResponse.fromJson(data);
    } on DioException {
      rethrow;
    }
  }
}
