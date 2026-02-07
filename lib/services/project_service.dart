import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

import '../models/project.dart';
import 'api_client.dart';

class ProjectService {
  final ApiClient _apiClient;

  ProjectService(this._apiClient);

  Future<List<Project>> listProjects({String? directory}) async {
    try {
      final response = await _apiClient.dio.get(
        '/project',
        queryParameters: {
          'directory': ?directory,
        },
      );
      final data = response.data as List;
      return data.map((item) {
        try {
          return Project.fromJson(item as Map<String, dynamic>);
        } catch (e) {
          debugPrint('[ProjectService] Failed to parse project: $e\nRaw: $item');
          rethrow;
        }
      }).toList();
    } on DioException {
      rethrow;
    }
  }

  Future<Project> getCurrentProject({String? directory}) async {
    try {
      final response = await _apiClient.dio.get(
        '/project/current',
        queryParameters: {
          'directory': ?directory,
        },
      );
      return Project.fromJson(response.data as Map<String, dynamic>);
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
    try {
      final response = await _apiClient.dio.patch(
        '/project/$projectID',
        data: {
          'name': ?name,
          'icon': ?icon,
        },
        queryParameters: {
          'directory': ?directory,
        },
      );
      return Project.fromJson(response.data as Map<String, dynamic>);
    } on DioException {
      rethrow;
    }
  }
}
