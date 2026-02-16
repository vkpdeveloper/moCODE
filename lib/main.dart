import 'package:firebase_core/firebase_core.dart';
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
import 'providers/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();
  final envFile = kReleaseMode ? '.prod.env' : '.dev.env';
  await dotenv.load(fileName: envFile);
  await Firebase.initializeApp();

  // Initialize download notifications
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

class MoCODEApp extends ConsumerWidget {
  const MoCODEApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(globalEventCoordinatorProvider);
    final router = ref.watch(routerProvider);

    return PathBootstrap(
      child: MaterialApp.router(
        title: 'moCODE',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        routerConfig: router,
      ),
    );
  }
}
