import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

enum AppLogLevel { debug, info, warning, error }

class AppLogEntry {
  const AppLogEntry({
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
    this.data,
  });

  final DateTime timestamp;
  final AppLogLevel level;
  final String tag;
  final String message;
  final Map<String, dynamic>? data;

  String toLine() {
    final ts = timestamp.toIso8601String();
    final lvl = switch (level) {
      AppLogLevel.debug => 'DEBUG',
      AppLogLevel.info => 'INFO',
      AppLogLevel.warning => 'WARN',
      AppLogLevel.error => 'ERROR',
    };
    final payload = data == null || data!.isEmpty ? '' : ' ${jsonEncode(data)}';
    return '[$ts] [$lvl] [$tag] $message$payload';
  }
}

class AppLogger {
  AppLogger._();

  static bool enabled = true;
  static int maxEntries = 1000;

  static final List<AppLogEntry> _entries = <AppLogEntry>[];
  static final StreamController<AppLogEntry> _streamController =
      StreamController<AppLogEntry>.broadcast();

  static Stream<AppLogEntry> get stream => _streamController.stream;

  static List<AppLogEntry> get entries =>
      List<AppLogEntry>.unmodifiable(_entries);

  static void debug(String tag, String message, {Map<String, dynamic>? data}) {
    _write(AppLogLevel.debug, tag, message, data: data);
  }

  static void info(String tag, String message, {Map<String, dynamic>? data}) {
    _write(AppLogLevel.info, tag, message, data: data);
  }

  static void warn(String tag, String message, {Map<String, dynamic>? data}) {
    _write(AppLogLevel.warning, tag, message, data: data);
  }

  static void error(String tag, String message, {Map<String, dynamic>? data}) {
    _write(AppLogLevel.error, tag, message, data: data);
  }

  static void clear() {
    _entries.clear();
  }

  static String dump({int? tail}) {
    final slice = tail == null || tail <= 0 || tail >= _entries.length
        ? _entries
        : _entries.sublist(_entries.length - tail);
    return slice.map((entry) => entry.toLine()).join('\n');
  }

  static void _write(
    AppLogLevel level,
    String tag,
    String message, {
    Map<String, dynamic>? data,
  }) {
    if (!enabled) return;
    final entry = AppLogEntry(
      timestamp: DateTime.now().toUtc(),
      level: level,
      tag: tag,
      message: message,
      data: data,
    );
    _entries.add(entry);
    if (_entries.length > maxEntries) {
      _entries.removeAt(0);
    }
    if (!_streamController.isClosed) {
      _streamController.add(entry);
    }
    debugPrint(entry.toLine());
  }
}
