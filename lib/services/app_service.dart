import 'package:dio/dio.dart';

import '../models/app_models.dart';
import '../models/server_type.dart';
import 'api_client.dart';
import '../utils/json_parser.dart';
import 'codex_app_server_service.dart';

class AppService {
  final ApiClient _apiClient;
  final ServerType _serverType;

  AppService(
    this._apiClient, {
    ServerType serverType = ServerType.openCode,
    CodexAppServerService? codex,
  }) : _serverType = serverType;

  bool get _useCodex => _serverType == ServerType.codex;

  Future<HealthInfo> getHealth() async {
    if (_useCodex) {
      return const HealthInfo(healthy: true, version: 'codex');
    }

    try {
      final response = await _apiClient.dio.get('/global/health');
      final data = parseJsonObjectBytes(response.data as List<int>);
      return HealthInfo.fromJson(data);
    } on DioException {
      rethrow;
    }
  }

  Future<VcsInfo> getVcsInfo({String? directory}) async {
    if (_useCodex) {
      return const VcsInfo(branch: null, commit: null, dirty: null);
    }

    try {
      final response = await _apiClient.dio.get(
        '/vcs',
        queryParameters: {'directory': ?directory},
      );
      final data = parseJsonObjectBytes(response.data as List<int>);
      return VcsInfo.fromJson(data);
    } on DioException {
      rethrow;
    }
  }

  Future<List<Command>> listCommands({String? directory}) async {
    if (_useCodex) return const [];

    try {
      final response = await _apiClient.dio.get(
        '/command',
        queryParameters: {'directory': ?directory},
      );
      final data = parseJsonListBytes(response.data as List<int>);
      return data
          .map((item) => Command.fromJson(item as Map<String, dynamic>))
          .toList();
    } on DioException {
      rethrow;
    }
  }

  Future<List<Agent>> listAgents({String? directory}) async {
    if (_useCodex) return const [];

    try {
      final response = await _apiClient.dio.get(
        '/agent',
        queryParameters: {'directory': ?directory},
      );
      final data = parseJsonListBytes(response.data as List<int>);
      return data
          .map((item) => Agent.fromJson(item as Map<String, dynamic>))
          .toList();
    } on DioException {
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> listSkills({String? directory}) async {
    if (_useCodex) return const [];

    try {
      final response = await _apiClient.dio.get(
        '/skill',
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
    if (_useCodex) return const [];

    try {
      final response = await _apiClient.dio.get(
        '/find/file',
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
    if (_useCodex) {
      return const AppConfig(raw: {'server': 'codex'});
    }

    try {
      final response = await _apiClient.dio.get(
        '/config',
        queryParameters: {'directory': ?directory},
      );
      final data = parseJsonObjectBytes(response.data as List<int>);
      return AppConfig.fromJson(data);
    } on DioException {
      rethrow;
    }
  }
}
