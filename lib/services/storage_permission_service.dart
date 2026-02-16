import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

class StoragePermissionService {
  static Future<bool> requestStoragePermission() async {
    if (Platform.isAndroid) {
      final status = await Permission.storage.status;

      if (status.isGranted) {
        return true;
      }

      final result = await Permission.storage.request();
      return result.isGranted;
    } else if (Platform.isIOS) {
      return true;
    }

    return false;
  }

  static Future<bool> checkStoragePermission() async {
    if (Platform.isAndroid) {
      final status = await Permission.storage.status;
      return status.isGranted;
    } else if (Platform.isIOS) {
      return true;
    }

    return false;
  }
}
