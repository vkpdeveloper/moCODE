import 'package:dio/dio.dart';

import '../models/app_models.dart';
import 'api_client.dart';
import '../utils/json_parser.dart';

class AppService {
  final ApiClient _apiClient;

  AppService(this._apiClient);

  Future<HealthInfo> getHealth() async {
    try {
      final response = await _apiClient.dio.get('/v1/health');
      final data = parseJsonObjectBytes(response.data as List<int>);
      return HealthInfo.fromJson(data);
    } on DioException {
      rethrow;
    }
  }

  Future<VcsInfo> getVcsInfo({String? directory}) async {
    try {
      final response = await _apiClient.dio.get(
        '/v1/vcs',
        queryParameters: {'directory': ?directory},
      );
      final data = parseJsonObjectBytes(response.data as List<int>);
      return VcsInfo.fromJson(data);
    } on DioException {
      rethrow;
    }
  }

  Future<List<Command>> listCommands({String? directory}) async {
    return const [];
  }

  Future<List<Agent>> listAgents({String? directory}) async {
    try {
      final response = await _apiClient.dio.get(
        '/v1/agents',
        queryParameters: {'directory': ?directory},
      );
      final data = parseJsonObjectBytes(response.data as List<int>);
      final agents = (data['agents'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>()
          .where(
            (agent) =>
                (agent['installState']?.toString() ?? '') != 'unavailable',
          )
          .map((agent) {
            final metadata =
                (agent['metadata'] as Map<String, dynamic>?) ??
                const <String, dynamic>{};
            final kind = agent['kind']?.toString();
            final source = agent['source']?.toString();
            final details = [
              if (kind != null && kind.isNotEmpty) kind,
              if (source != null && source.isNotEmpty) source,
            ].join(' via ');
            final registryDescription =
                metadata['registryDescription']?.toString();
            return Agent(
              name: agent['name']?.toString() ?? '',
              description: (registryDescription != null &&
                      registryDescription.isNotEmpty)
                  ? registryDescription
                  : (details.isEmpty ? null : details),
              iconSvg: metadata['iconSvg']?.toString(),
              mode: agent['id']?.toString(),
            );
          })
          .toList();
      return agents;
    } on DioException {
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> listSkills({String? directory}) async {
    try {
      final response = await _apiClient.dio.get(
        '/v1/skills',
        queryParameters: {'directory': ?directory},
      );
      final data = parseJsonListBytes(response.data as List<int>);
      return data.cast<Map<String, dynamic>>();
    } on DioException {
      rethrow;
    }
  }

  Future<List<String>> findFiles({
    required String query,
    String? directory,
    int? limit,
  }) async {
    try {
      final response = await _apiClient.dio.get(
        '/v1/files/search',
        queryParameters: {
          'query': query,
          'directory': ?directory,
          'limit': ?limit,
        },
      );
      final data = parseJsonListBytes(response.data as List<int>);
      return data.cast<String>();
    } on DioException {
      rethrow;
    }
  }

  Future<AppConfig> getConfig({String? directory}) async {
    return const AppConfig(raw: <String, dynamic>{});
  }
}
