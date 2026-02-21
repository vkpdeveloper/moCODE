import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';

import '../utils/json_parser.dart';
import 'account_api_client.dart';

class AsrService {
  final AccountApiClient _apiClient;

  AsrService(this._apiClient);

  Future<AsrTranscriptionResult> transcribe(
    String audioPath, {
    String? language,
    String? idToken,
  }) async {
    final file = File(audioPath);
    if (!await file.exists()) {
      throw AsrException('Audio file not found');
    }

    final duration = await _getAudioDuration(audioPath);

    final fileName = audioPath.split('/').last;
    final mimeType = _getMimeType(fileName);

    final formData = FormData.fromMap({
      'audio': await MultipartFile.fromFile(
        audioPath,
        filename: fileName,
        contentType: DioMediaType.parse(mimeType),
      ),
      if (language != null && language.isNotEmpty) 'language': language,
      'durationMs': duration,
    });

    final headers = <String, dynamic>{'Content-Type': 'multipart/form-data'};

    if (idToken != null && idToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $idToken';
    }

    try {
      final response = await _apiClient.dio.post(
        '/api/v1/asr/transcribe',
        data: formData,
        options: Options(headers: headers),
      );

      if (response.statusCode == 200) {
        final data = parseJsonObjectBytes(response.data);
        return AsrTranscriptionResult.fromJson(data);
      } else {
        throw AsrException('Transcription failed: ${response.statusCode}');
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw AsrException('Unauthorized. Please sign in again.');
      }
      final errorMsg =
          e.response?.data?['error'] ?? e.message ?? 'Unknown error';
      throw AsrException('Transcription failed: $errorMsg');
    }
  }

  Future<int> _getAudioDuration(String audioPath) async {
    final player = AudioPlayer();
    try {
      await player.setSource(DeviceFileSource(audioPath));
      final duration = await player.getDuration();
      if (duration != null) {
        return duration.inMilliseconds;
      }
    } catch (_) {
      return 0;
    } finally {
      await player.dispose();
    }
    return 0;
  }

  String _getMimeType(String fileName) {
    final ext = fileName.toLowerCase().split('.').last;
    return switch (ext) {
      'm4a' => 'audio/mp4',
      'mp3' => 'audio/mpeg',
      'wav' => 'audio/wav',
      'ogg' => 'audio/ogg',
      'webm' => 'audio/webm',
      'aac' => 'audio/aac',
      _ => 'audio/mp4',
    };
  }
}

class AsrTranscriptionResult {
  final String text;

  AsrTranscriptionResult({required this.text});

  factory AsrTranscriptionResult.fromJson(Map<String, dynamic> json) {
    return AsrTranscriptionResult(text: json['text'] as String? ?? '');
  }
}

class AsrException implements Exception {
  final String message;

  AsrException(this.message);

  @override
  String toString() => message;
}
