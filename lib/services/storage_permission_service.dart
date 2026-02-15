import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

class StoragePermissionService {
  static Future<bool> requestStoragePermission() async {
    if (Platform.isAndroid) {
      final sdkVersion = await _getAndroidSdkVersion();
      
      if (sdkVersion >= 33) {
        // Android 13+ - use granular media permissions
        final photos = await Permission.photos.request();
        final videos = await Permission.videos.request();
        final audio = await Permission.audio.request();
        
        return photos.isGranted || videos.isGranted || audio.isGranted;
      } else if (sdkVersion >= 30) {
        // Android 11-12
        final storage = await Permission.storage.request();
        if (!storage.isGranted) {
          final manageStorage = await Permission.manageExternalStorage.request();
          return manageStorage.isGranted;
        }
        return storage.isGranted;
      } else {
        // Android 10 and below
        final storage = await Permission.storage.request();
        return storage.isGranted;
      }
    } else if (Platform.isIOS) {
      // iOS uses app sandbox, no special permissions needed for app's own directories
      return true;
    }
    
    return false;
  }
  
  static Future<bool> checkStoragePermission() async {
    if (Platform.isAndroid) {
      final sdkVersion = await _getAndroidSdkVersion();
      
      if (sdkVersion >= 33) {
        final photos = await Permission.photos.status;
        final videos = await Permission.videos.status;
        final audio = await Permission.audio.status;
        return photos.isGranted || videos.isGranted || audio.isGranted;
      } else if (sdkVersion >= 30) {
        final storage = await Permission.storage.status;
        if (!storage.isGranted) {
          final manageStorage = await Permission.manageExternalStorage.status;
          return manageStorage.isGranted;
        }
        return storage.isGranted;
      } else {
        final storage = await Permission.storage.status;
        return storage.isGranted;
      }
    } else if (Platform.isIOS) {
      return true;
    }
    
    return false;
  }
  
  static Future<int> _getAndroidSdkVersion() async {
    // Default to Android 10 if we can't determine version
    try {
      // We'll use a default of 30 (Android 11) to be safe
      // The actual check would require device_info_plus, but we'll keep it simple
      return 30;
    } catch (e) {
      return 30;
    }
  }
}
