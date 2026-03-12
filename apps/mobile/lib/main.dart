import 'dart:io' show Platform;
import 'dart:ui';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router/app_router.dart';
import 'services/download_notification_service.dart';
import 'theme/app_theme.dart';
import 'widgets/active_session_manager.dart';
import 'widgets/path_bootstrap.dart';
import 'widgets/update_dialog.dart';
import 'providers/providers.dart';
import 'services/in_app_update_service.dart';
import 'services/app_logger.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();
  await AppLogger.instance.initialize();
  FlutterError.onError = (details) {
    AppLogger.instance.error(
      'Flutter framework error',
      scope: 'flutter',
      data: {
        'library': details.library,
        'context': details.context?.toDescription(),
      },
      error: details.exception,
      stackTrace: details.stack,
    );
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    AppLogger.instance.error(
      'Uncaught platform error',
      scope: 'flutter',
      error: error,
      stackTrace: stackTrace,
    );
    return false;
  };

  final envFile = kReleaseMode ? '.prod.env' : '.dev.env';
  await dotenv.load(fileName: envFile);
  await Firebase.initializeApp();

  if (kReleaseMode) {
    await FirebaseAppCheck.instance.activate(
      androidProvider: AndroidProvider.playIntegrity,
      appleProvider: AppleProvider.appAttest,
    );
  } else {
    await FirebaseAppCheck.instance.activate(
      androidProvider: AndroidProvider.debug,
      appleProvider: AppleProvider.debug,
    );
  }

  await DownloadNotificationService().initialize();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppTheme.background,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const ProviderScope(child: ActiveSessionManager(child: MoCODEApp())));
}

class MoCODEApp extends ConsumerStatefulWidget {
  const MoCODEApp({super.key});

  @override
  ConsumerState<MoCODEApp> createState() => _MoCODEAppState();
}

class _MoCODEAppState extends ConsumerState<MoCODEApp>
    with WidgetsBindingObserver {
  bool _isCheckingForUpdates = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkForUpdates();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkForUpdates();
    }
  }

  Future<void> _checkForUpdates() async {
    if (!Platform.isAndroid || !kReleaseMode || _isCheckingForUpdates) return;

    _isCheckingForUpdates = true;
    final updateService = ref.read(inAppUpdateServiceProvider);
    try {
      await updateService.checkForUpdate();
      final mustUpdate =
          updateService.status == UpdateStatus.updateAvailable ||
          updateService.status == UpdateStatus.updateDownloaded;
      ref.read(updateAvailableProvider.notifier).state = mustUpdate;
    } finally {
      _isCheckingForUpdates = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(globalEventCoordinatorProvider);
    final router = ref.watch(routerProvider);

    return PathBootstrap(
      child: MaterialApp.router(
        title: 'moCODE',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        routerConfig: router,
        builder: (context, child) {
          return UpdateOverlay(child: child ?? const SizedBox.shrink());
        },
      ),
    );
  }
}
