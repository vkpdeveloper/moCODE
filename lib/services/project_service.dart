import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

import '../models/project.dart';
import '../models/server_type.dart';
import 'api_client.dart';
import '../utils/json_parser.dart';
import 'codex_app_server_service.dart';

class ProjectService {
  final ApiClient _apiClient;
  final ServerType _serverType;
  final CodexAppServerService? _codex;
  final String Function() _workspaceProvider;

  ProjectService(
    this._apiClient, {
    ServerType serverType = ServerType.openCode,
    CodexAppServerService? codex,
    required String Function() workspaceProvider,
  }) : _serverType = serverType,
       _codex = codex,
       _workspaceProvider = workspaceProvider;

  bool get _useCodex => _serverType == ServerType.codex;

  Future<List<Project>> listProjects({String? directory}) async {
    if (_useCodex) {
      final workspace = (directory ?? _workspaceProvider()).trim();
      if (workspace.isEmpty) return const [];
      return [
        (_codex ?? (throw StateError('Codex service missing'))).pseudoProject(
          workspace,
        ),
      ];
    }

    try {
      final response = await _apiClient.dio.get(
        '/project',
        queryParameters: {'directory': ?directory},
      );
      final data = parseJsonListBytes(response.data as List<int>);
      return data.map((item) {
        try {
          return Project.fromJson(item as Map<String, dynamic>);
        } catch (e) {
          debugPrint(
            '[ProjectService] Failed to parse project: $e\nRaw: $item',
          );
          rethrow;
        }
      }).toList();
    } on DioException {
      rethrow;
    }
  }

  Future<Project> getCurrentProject({String? directory}) async {
    if (_useCodex) {
      final workspace = (directory ?? _workspaceProvider()).trim();
      return (_codex ?? (throw StateError('Codex service missing')))
          .pseudoProject(workspace);
    }

    try {
      final response = await _apiClient.dio.get(
        '/project/current',
        queryParameters: {'directory': ?directory},
      );
      final data = parseJsonObjectBytes(response.data as List<int>);
      return Project.fromJson(data);
    } on DioException {
      rethrow;
    }
  }

  Future<Project> updateProject(
    String projectID, {
    String? name,
    Map<String, String>? icon,
    String? directory,
  }) async {
    if (_useCodex) {
      return getCurrentProject(directory: directory);
    }

    try {
      final response = await _apiClient.dio.patch(
        '/project/$projectID',
        data: {'name': ?name, 'icon': ?icon},
        queryParameters: {'directory': ?directory},
      );
      final data = parseJsonObjectBytes(response.data as List<int>);
      return Project.fromJson(data);
    } on DioException {
      rethrow;
    }
  }
}
