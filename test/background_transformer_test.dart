import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mecode/services/background_transformer.dart' as custom;
import 'package:mecode/models/session.dart';

void main() {
  test(
    'BackgroundTransformer result can be parsed by Session.fromJson',
    () async {
      // Mock data matching Session model
      final mockSessions = [
        {
          'id': 'session1',
          'slug': 'slug-1',
          'projectID': 'proj1',
          'directory': '/tmp',
          'title': 'Test Session 1',
          'version': '1.0',
          'time': {'created': 1234567890, 'updated': 1234567890},
        },
      ];
      final jsonString = jsonEncode(mockSessions);

      final dio = Dio();
      dio.transformer = custom.BackgroundTransformer();

      final transformer = custom.BackgroundTransformer();
      final responseBody = ResponseBody.fromString(
        jsonString,
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

      final options = RequestOptions(path: '/session');

      final result = await transformer.transformResponse(options, responseBody);

      expect(result, isA<List>());
      final list = result as List;
      expect(list.length, 1);

      // Attempt parsing
      try {
        final session = Session.fromJson(list[0] as Map<String, dynamic>);
        expect(session.id, 'session1');
      } catch (e) {
        fail('Failed to parse session: $e');
      }
    },
  );
}
