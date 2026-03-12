import 'package:dio/dio.dart';

import '../models/acp_models.dart';
import '../models/project.dart';
import '../utils/json_parser.dart';
import 'api_client.dart';
import 'app_logger.dart';

class ProjectService {
  final ApiClient _apiClient;

  ProjectService(this._apiClient);

  Future<List<Project>> listProjects({String? directory}) async {
    try {
      final response = await _apiClient.dio.get('/v1/projects');
      final data = parseJsonObjectBytes(response.data as List<int>);
      final projects = (data['projects'] as List<dynamic>? ?? const [])
          .map((item) {
            try {
              return projectFromAcpJson(item as Map<String, dynamic>);
            } catch (e) {
              AppLogger.instance.error(
                'Failed to parse project payload',
                scope: 'projectService',
                data: {'raw': item},
                error: e,
              );
              rethrow;
            }
          })
          .toList();
      if (directory == null || directory.isEmpty) {
        return projects;
      }
      return projects.where((project) => project.worktree == directory).toList();
    } on DioException {
      rethrow;
    }
  }

  Future<Project> getCurrentProject({String? directory}) async {
    final projects = await listProjects();
    if (projects.isEmpty) {
      throw StateError('Project not found.');
    }
    if (directory == null || directory.isEmpty) {
      return projects.first;
    }
    final matches = projects.where((project) => project.worktree == directory);
    return matches.isNotEmpty ? matches.first : projects.first;
  }

  Future<Project> updateProject(
    String projectID, {
    String? name,
    Map<String, String>? icon,
    String? directory,
  }) async {
    try {
      final response = await _apiClient.dio.patch(
        '/v1/projects/$projectID',
        data: {
          'displayName': name,
        },
      );
      final data = parseJsonObjectBytes(response.data as List<int>);
      return projectFromAcpJson(data['project'] as Map<String, dynamic>);
    } on DioException {
      rethrow;
    }
  }

  Future<Project> openProject(String path) async {
    try {
      final response = await _apiClient.dio.post(
        '/v1/projects/open',
        data: {'path': path},
      );
      final data = parseJsonObjectBytes(response.data as List<int>);
      return projectFromAcpJson(data['project'] as Map<String, dynamic>);
    } on DioException {
      rethrow;
    }
  }
}
