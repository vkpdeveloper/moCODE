import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

class DownloadNotificationService {
  static final DownloadNotificationService _instance = DownloadNotificationService._internal();
  factory DownloadNotificationService() => _instance;
  DownloadNotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/launcher_icon');
    
    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(initSettings);
    
    if (Platform.isAndroid) {
      final androidPlugin = _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
    }
    
    _initialized = true;
  }

  Future<void> showDownloadStart(String fileName) async {
    if (!_initialized) await initialize();
    
    if (Platform.isAndroid) {
      await _notifications.show(
        fileName.hashCode,
        'Download Started',
        'Downloading $fileName...',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'downloads',
            'Downloads',
            channelDescription: 'File download notifications',
            importance: Importance.low,
            priority: Priority.low,
            showProgress: true,
            maxProgress: 100,
            progress: 0,
            ongoing: true,
            autoCancel: false,
          ),
        ),
      );
    }
  }

  Future<void> updateDownloadProgress(
    String fileName,
    int progress,
    int total,
  ) async {
    if (!_initialized) await initialize();
    
    if (Platform.isAndroid && total > 0) {
      final percentage = (progress / total * 100).round();
      
      await _notifications.show(
        fileName.hashCode,
        'Downloading $fileName',
        '$percentage% - ${(_formatBytes(progress))} / ${(_formatBytes(total))}',
        NotificationDetails(
          android: AndroidNotificationDetails(
            'downloads',
            'Downloads',
            channelDescription: 'File download notifications',
            importance: Importance.low,
            priority: Priority.low,
            showProgress: true,
            maxProgress: 100,
            progress: percentage,
            ongoing: true,
            autoCancel: false,
            onlyAlertOnce: true,
          ),
        ),
      );
    }
  }

  Future<void> showDownloadComplete(String fileName, String path) async {
    if (!_initialized) await initialize();
    
    if (Platform.isAndroid) {
      await _notifications.show(
        fileName.hashCode,
        'Download Complete',
        '$fileName downloaded successfully',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'downloads',
            'Downloads',
            channelDescription: 'File download notifications',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            ongoing: false,
            autoCancel: true,
          ),
        ),
      );
    }
  }

  Future<void> showDownloadError(String fileName, String error) async {
    if (!_initialized) await initialize();
    
    if (Platform.isAndroid) {
      await _notifications.show(
        fileName.hashCode,
        'Download Failed',
        'Failed to download $fileName: $error',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'downloads',
            'Downloads',
            channelDescription: 'File download notifications',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            ongoing: false,
            autoCancel: true,
          ),
        ),
      );
    }
  }

  Future<void> cancelNotification(String fileName) async {
    if (!_initialized) return;
    await _notifications.cancel(fileName.hashCode);
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
