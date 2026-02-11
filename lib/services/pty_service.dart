import 'package:dio/dio.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/pty.dart';
import '../utils/json_parser.dart';
import 'api_client.dart';

class PtyService {
  final ApiClient _apiClient;

  PtyService(this._apiClient);

  Future<PtyInfo> createPty({
    required String command,
    List<String> args = const [],
    required String cwd,
    String? title,
    Map<String, String>? env,
    String? directory,
  }) async {
    try {
      final response = await _apiClient.dio.post(
        '/pty',
        data: {
          'command': command,
          'args': args,
          'cwd': cwd,
          if (title != null) 'title': title,
          if (env != null) 'env': env,
        },
        queryParameters: {'directory': directory},
      );
      final data = parseJsonObjectBytes(response.data as List<int>);
      return PtyInfo.fromJson(data);
    } on DioException catch (e) {
      final data = parseJsonObjectBytes(e.response?.data as List<int>);
      print(data);
      rethrow;
    }
  }

  Future<PtyInfo> getPty(String id, {String? directory}) async {
    try {
      final response = await _apiClient.dio.get(
        '/pty/$id',
        queryParameters: {'directory': directory},
      );
      final data = parseJsonObjectBytes(response.data as List<int>);
      return PtyInfo.fromJson(data);
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is List<int>) {
        parseJsonObjectBytes(data);
      }
      rethrow;
    }
  }

  Future<PtyInfo> updatePty(
    String id, {
    String? title,
    ({int rows, int cols})? size,
    String? directory,
  }) async {
    try {
      final payload = <String, dynamic>{};
      if (title != null) payload['title'] = title;
      if (size != null) {
        payload['size'] = {'rows': size.rows, 'cols': size.cols};
      }
      final response = await _apiClient.dio.put(
        '/pty/$id',
        data: payload,
        queryParameters: {'directory': directory},
      );
      final data = parseJsonObjectBytes(response.data as List<int>);
      return PtyInfo.fromJson(data);
    } on DioException {
      rethrow;
    }
  }

  Future<void> removePty(String id, {String? directory}) async {
    try {
      await _apiClient.dio.delete(
        '/pty/$id',
        queryParameters: {'directory': directory},
      );
    } on DioException {
      rethrow;
    }
  }

  WebSocketChannel connect(String id, {String? directory}) {
    final url = _apiClient.buildWsUrl(
      '/pty/$id/connect',
      queryParameters: {'directory': directory},
    );
    return WebSocketChannel.connect(Uri.parse(url));
  }
}
