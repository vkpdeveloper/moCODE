import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart' as log_pkg;
import 'package:path_provider/path_provider.dart';

enum AppLogLevel { debug, info, warning, error }

class AppLogger {
  AppLogger._() {
    _logger = log_pkg.Logger(
      level: kReleaseMode ? log_pkg.Level.info : log_pkg.Level.debug,
      filter: _AppLogFilter(),
      printer: _StructuredLogPrinter(this),
      output: _AppLogOutput(this),
    );
  }

  static final AppLogger instance = AppLogger._();

  static const int _maxDepth = 5;
  static const int _maxStringLength = 500;
  static const int _maxCollectionItems = 20;
  static final RegExp _redactedKey = RegExp(
    r'authorization|token|secret|password|cookie|api[-_]?key',
    caseSensitive: false,
  );

  Future<void>? _initializing;
  IOSink? _sink;
  String? _logFilePath;
  late final log_pkg.Logger _logger;

  String? get logFilePath => _logFilePath;

  Future<void> initialize() {
    final current = _initializing;
    if (current != null) {
      return current;
    }

    final next = _initializeInternal();
    _initializing = next;
    return next;
  }

  Future<void> _initializeInternal() async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      final logDir = Directory('${supportDir.path}/logs');
      await logDir.create(recursive: true);
      final file = File('${logDir.path}/app.log');
      _sink = file.openWrite(mode: FileMode.append);
      _logFilePath = file.path;
      info(
        'app logger initialized',
        scope: 'logger',
        data: {'path': _logFilePath},
      );
    } catch (error, stackTrace) {
      developer.log(
        'Failed to initialize app logger: $error',
        name: 'moCODE.logger',
        level: 1000,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void debug(String message, {String scope = 'app', Object? data}) {
    _log(AppLogLevel.debug, message, scope: scope, data: data);
  }

  void info(String message, {String scope = 'app', Object? data}) {
    _log(AppLogLevel.info, message, scope: scope, data: data);
  }

  void warning(String message, {String scope = 'app', Object? data}) {
    _log(AppLogLevel.warning, message, scope: scope, data: data);
  }

  void error(
    String message, {
    String scope = 'app',
    Object? data,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log(
      AppLogLevel.error,
      message,
      scope: scope,
      data: data,
      error: error,
      stackTrace: stackTrace,
    );
  }

  void _log(
    AppLogLevel level,
    String message, {
    required String scope,
    Object? data,
    Object? error,
    StackTrace? stackTrace,
  }) {
    final payload = <String, Object?>{
      'timestamp': DateTime.now().toIso8601String(),
      'level': level.name,
      'scope': scope,
      'message': _truncate(message),
      if (data != null) 'data': sanitize(data),
      if (error != null) 'error': sanitize(error),
      if (stackTrace != null) 'stackTrace': _truncate(stackTrace.toString()),
    };

    _logger.log(
      _toLoggerLevel(level),
      payload,
      error: error,
      stackTrace: stackTrace,
    );
  }

  int _toDeveloperLevel(AppLogLevel level) {
    return switch (level) {
      AppLogLevel.debug => 500,
      AppLogLevel.info => 800,
      AppLogLevel.warning => 900,
      AppLogLevel.error => 1000,
    };
  }

  log_pkg.Level _toLoggerLevel(AppLogLevel level) {
    return switch (level) {
      AppLogLevel.debug => log_pkg.Level.debug,
      AppLogLevel.info => log_pkg.Level.info,
      AppLogLevel.warning => log_pkg.Level.warning,
      AppLogLevel.error => log_pkg.Level.error,
    };
  }

  AppLogLevel _fromLoggerLevel(log_pkg.Level level) {
    return switch (level) {
      log_pkg.Level.trace || log_pkg.Level.debug => AppLogLevel.debug,
      log_pkg.Level.info => AppLogLevel.info,
      log_pkg.Level.warning => AppLogLevel.warning,
      log_pkg.Level.error || log_pkg.Level.fatal => AppLogLevel.error,
      _ => AppLogLevel.info,
    };
  }

  Object? sanitize(Object? value, {int depth = 0, String key = ''}) {
    if (depth > _maxDepth) {
      return '[max-depth]';
    }
    if (value == null) {
      return null;
    }
    if (value is String) {
      return _redactedKey.hasMatch(key) ? _mask(value) : _truncate(value);
    }
    if (value is num || value is bool) {
      return value;
    }
    if (value is Uint8List) {
      return '[${value.length} bytes]';
    }
    if (value is List<int>) {
      return '[${value.length} bytes]';
    }
    if (value is FormData) {
      return <String, Object?>{
        'fields': value.fields
            .take(_maxCollectionItems)
            .map((entry) => <String, Object?>{
                  'name': entry.key,
                  'value': sanitize(entry.value, depth: depth + 1, key: entry.key),
                })
            .toList(growable: false),
        'files': value.files
            .take(_maxCollectionItems)
            .map((entry) => <String, Object?>{
                  'field': entry.key,
                  'filename': entry.value.filename,
                  'contentType': entry.value.contentType?.mimeType,
                })
            .toList(growable: false),
      };
    }
    if (value is DioException) {
      return <String, Object?>{
        'type': value.type.name,
        'message': _truncate(value.message ?? ''),
        'statusCode': value.response?.statusCode,
        'request': sanitizeRequestOptions(value.requestOptions),
        if (value.response != null) 'response': sanitizeResponse(value.response!),
      };
    }
    if (value is RequestOptions) {
      return sanitizeRequestOptions(value);
    }
    if (value is Response<dynamic>) {
      return sanitizeResponse(value);
    }
    if (value is Map) {
      final output = <String, Object?>{};
      for (final entry in value.entries.take(_maxCollectionItems)) {
        final entryKey = entry.key.toString();
        output[entryKey] = _redactedKey.hasMatch(entryKey)
            ? _mask(entry.value?.toString() ?? '')
            : sanitize(
                entry.value,
                depth: depth + 1,
                key: entryKey,
              );
      }
      if (value.length > _maxCollectionItems) {
        output['__truncatedKeys'] = value.length - _maxCollectionItems;
      }
      return output;
    }
    if (value is Iterable) {
      final items = value
          .take(_maxCollectionItems)
          .map((item) => sanitize(item, depth: depth + 1, key: key))
          .toList(growable: false);
      if (value.length > _maxCollectionItems) {
        return [
          ...items,
          '... ${value.length - _maxCollectionItems} more items',
        ];
      }
      return items;
    }
    if (value is Error) {
      return <String, Object?>{
        'runtimeType': value.runtimeType.toString(),
        'message': _truncate(value.toString()),
        'stackTrace': _truncate(StackTrace.current.toString()),
      };
    }
    return _truncate(value.toString());
  }

  Map<String, Object?> sanitizeRequestOptions(RequestOptions options) {
    return <String, Object?>{
      'method': options.method,
      'baseUrl': options.baseUrl,
      'path': options.path,
      'queryParameters': sanitize(options.queryParameters),
      'headers': sanitize(options.headers),
      'data': sanitize(options.data),
    };
  }

  Map<String, Object?> sanitizeResponse(Response<dynamic> response) {
    return <String, Object?>{
      'statusCode': response.statusCode,
      'headers': sanitize(response.headers.map),
      'data': sanitize(_responseBodyPreview(response)),
    };
  }

  Object? _responseBodyPreview(Response<dynamic> response) {
    final data = response.data;
    if (data == null) {
      return null;
    }
    if (data is List<int>) {
      final contentType =
          response.headers.value(Headers.contentTypeHeader) ?? '';
      if (contentType.contains('application/json')) {
        try {
          return sanitize(jsonDecode(utf8.decode(data)));
        } catch (_) {
          return '[${data.length} bytes of invalid JSON]';
        }
      }
      return '[${data.length} bytes]';
    }
    return data;
  }

  String _truncate(String value) {
    if (value.length <= _maxStringLength) {
      return value;
    }
    return '${value.substring(0, _maxStringLength)}... (${value.length} chars)';
  }

  String _mask(String value) {
    if (value.length <= 8) {
      return '***';
    }
    return '${value.substring(0, 3)}***${value.substring(value.length - 3)}';
  }
}

class _AppLogFilter extends log_pkg.LogFilter {
  @override
  bool shouldLog(log_pkg.LogEvent event) {
    final configured = level ?? log_pkg.Level.debug;
    return event.level >= configured;
  }
}

class _StructuredLogPrinter extends log_pkg.LogPrinter {
  _StructuredLogPrinter(this._appLogger);

  final AppLogger _appLogger;

  @override
  List<String> log(log_pkg.LogEvent event) {
    final payload = event.message is Map
        ? Map<String, Object?>.from(event.message as Map)
        : <String, Object?>{
            'timestamp': event.time.toIso8601String(),
            'level': event.level.name,
            'scope': 'app',
            'message': _appLogger.sanitize(event.message),
          };

    payload['timestamp'] ??= event.time.toIso8601String();
    payload['level'] ??= event.level.name;
    payload['scope'] ??= 'app';

    if (event.error != null && !payload.containsKey('error')) {
      payload['error'] = _appLogger.sanitize(event.error);
    }
    if (event.stackTrace != null && !payload.containsKey('stackTrace')) {
      payload['stackTrace'] = _appLogger.sanitize(event.stackTrace.toString());
    }

    return [jsonEncode(payload)];
  }
}

class _AppLogOutput extends log_pkg.LogOutput {
  _AppLogOutput(this._appLogger);

  final AppLogger _appLogger;

  @override
  void output(log_pkg.OutputEvent event) {
    for (final line in event.lines) {
      var scope = 'app';
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map && decoded['scope'] is String) {
          scope = decoded['scope'] as String;
        }
      } catch (_) {
        // Ignore malformed log payloads and keep the raw line.
      }

      developer.log(
        line,
        name: 'moCODE.$scope',
        level: _appLogger._toDeveloperLevel(
          _appLogger._fromLoggerLevel(event.level),
        ),
        error: event.origin.error,
        stackTrace: event.origin.stackTrace,
      );

      final sink = _appLogger._sink;
      if (sink != null) {
        sink.writeln(line);
        unawaited(sink.flush());
      }
    }
  }
}

class AppLogInterceptor extends Interceptor {
  AppLogInterceptor({required this.clientName});

  final String clientName;

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    options.extra['requestStartedAt'] = DateTime.now();
    AppLogger.instance.info(
      'HTTP request',
      scope: 'http.$clientName',
      data: AppLogger.instance.sanitizeRequestOptions(options),
    );
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    final startedAt = response.requestOptions.extra['requestStartedAt'];
    final durationMs = startedAt is DateTime
        ? DateTime.now().difference(startedAt).inMilliseconds
        : null;
    AppLogger.instance.info(
      'HTTP response',
      scope: 'http.$clientName',
      data: {
        ...AppLogger.instance.sanitizeResponse(response),
        'durationMs': ?durationMs,
      },
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final startedAt = err.requestOptions.extra['requestStartedAt'];
    final durationMs = startedAt is DateTime
        ? DateTime.now().difference(startedAt).inMilliseconds
        : null;
    AppLogger.instance.error(
      'HTTP error',
      scope: 'http.$clientName',
      data: {
        'request': AppLogger.instance.sanitizeRequestOptions(err.requestOptions),
        'durationMs': ?durationMs,
      },
      error: AppLogger.instance.sanitize(err),
      stackTrace: err.stackTrace,
    );
    handler.next(err);
  }
}
