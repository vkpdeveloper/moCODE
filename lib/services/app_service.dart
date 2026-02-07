import 'package:dio/dio.dart';

import '../models/app_models.dart';
import 'api_client.dart';

class AppService {
  final ApiClient _apiClient;

  AppService(this._apiClient);

  Future<HealthInfo> getHealth() async {
    try {
      final response = await _apiClient.dio.get('/global/health');
      return HealthInfo.fromJson(response.data as Map<String, dynamic>);
    } on DioException {
      rethrow;
    }
  }

  Future<VcsInfo> getVcsInfo({String? directory}) async {
    try {
      final response = await _apiClient.dio.get(
        '/vcs',
        queryParameters: {
          'directory': ?directory,
        },
      );
      return VcsInfo.fromJson(response.data as Map<String, dynamic>);
    } on DioException {
      rethrow;
    }
  }

  Future<List<Command>> listCommands({String? directory}) async {
    try {
      final response = await _apiClient.dio.get(
        '/command',
        queryParameters: {
          'directory': ?directory,
        },
      );
      final data = response.data as List;
      return data
          .map((item) => Command.fromJson(item as Map<String, dynamic>))
          .toList();
    } on DioException {
      rethrow;
    }
  }

  Future<List<Agent>> listAgents({String? directory}) async {
    try {
      final response = await _apiClient.dio.get(
        '/agent',
        queryParameters: {
          'directory': ?directory,
        },
      );
      final data = response.data as List;
      return data
          .map((item) => Agent.fromJson(item as Map<String, dynamic>))
          .toList();
    } on DioException {
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> listSkills({String? directory}) async {
    try {
      final response = await _apiClient.dio.get(
        '/skill',
        queryParameters: {
          'directory': ?directory,
        },
      );
      final data = response.data as List;
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
        '/find/file',
        queryParameters: {
          'query': query,
          'directory': ?directory,
          'limit': ?limit,
        },
      );
      final data = response.data as List;
      return data.cast<String>();
    } on DioException {
      rethrow;
    }
  }

  Future<AppConfig> getConfig({String? directory}) async {
    try {
      final response = await _apiClient.dio.get(
        '/config',
        queryParameters: {
          'directory': ?directory,
        },
      );
      return AppConfig.fromJson(response.data as Map<String, dynamic>);
    } on DioException {
      rethrow;
    }
  }
}
