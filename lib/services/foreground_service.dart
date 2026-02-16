import 'package:flutter_foreground_task/flutter_foreground_task.dart';

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(SshBackgroundHandler());
}

class SshBackgroundHandler extends TaskHandler {
  int _eventCount = 0;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {
    _eventCount++;
    FlutterForegroundTask.updateService(
      notificationTitle: 'moCODE',
      notificationText: 'SSH active - ${_eventCount * 15}s',
    );
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {}

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'disconnect') {
      FlutterForegroundTask.stopService();
    }
  }
}

class ForegroundServiceManager {
  static final ForegroundServiceManager _instance =
      ForegroundServiceManager._internal();
  factory ForegroundServiceManager() => _instance;
  ForegroundServiceManager._internal();

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  Future<void> startService() async {
    if (_isRunning) return;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'ssh_connection',
        channelName: 'SSH Connection',
        channelDescription: 'Keeps SSH connection alive in background',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(15000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    final result = await FlutterForegroundTask.startService(
      notificationTitle: 'moCODE',
      notificationText: 'SSH connection active',
      callback: startCallback,
    );
    _isRunning = result is ServiceRequestSuccess;
  }

  Future<void> stopService() async {
    if (!_isRunning) return;
    await FlutterForegroundTask.stopService();
    _isRunning = false;
  }

  void updateNotification({String? title, String? body}) {
    if (_isRunning && title != null && body != null) {
      FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: body,
      );
    }
  }
}
