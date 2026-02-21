import 'dart:io';

import 'package:dio/dio.dart';

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

    final fileName = audioPath.split('/').last;
    final mimeType = _getMimeType(fileName);

    final formData = FormData.fromMap({
      'audio': await MultipartFile.fromFile(
        audioPath,
        filename: fileName,
        contentType: DioMediaType.parse(mimeType),
      ),
      if (language != null && language.isNotEmpty) 'language': language,
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
        final data = response.data as Map<String, dynamic>;
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
  final List<AsrSegment> segments;
  final List<AsrWord> words;
  final String language;
  final double duration;

  AsrTranscriptionResult({
    required this.text,
    required this.segments,
    required this.words,
    required this.language,
    required this.duration,
  });

  factory AsrTranscriptionResult.fromJson(Map<String, dynamic> json) {
    return AsrTranscriptionResult(
      text: json['text'] as String? ?? '',
      segments:
          (json['segments'] as List<dynamic>?)
              ?.map((s) => AsrSegment.fromJson(s as Map<String, dynamic>))
              .toList() ??
          [],
      words:
          (json['words'] as List<dynamic>?)
              ?.map((w) => AsrWord.fromJson(w as Map<String, dynamic>))
              .toList() ??
          [],
      language: json['language'] as String? ?? 'en',
      duration: (json['duration'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class AsrSegment {
  final String text;
  final double start;
  final double end;

  AsrSegment({required this.text, required this.start, required this.end});

  factory AsrSegment.fromJson(Map<String, dynamic> json) {
    return AsrSegment(
      text: json['text'] as String? ?? '',
      start: (json['start'] as num?)?.toDouble() ?? 0.0,
      end: (json['end'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class AsrWord {
  final String word;
  final double start;
  final double end;
  final double confidence;

  AsrWord({
    required this.word,
    required this.start,
    required this.end,
    required this.confidence,
  });

  factory AsrWord.fromJson(Map<String, dynamic> json) {
    return AsrWord(
      word: json['word'] as String? ?? '',
      start: (json['start'] as num?)?.toDouble() ?? 0.0,
      end: (json['end'] as num?)?.toDouble() ?? 0.0,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class AsrException implements Exception {
  final String message;

  AsrException(this.message);

  @override
  String toString() => message;
}
