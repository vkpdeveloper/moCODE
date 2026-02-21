import 'dart:io' show Platform;
import 'package:in_app_update/in_app_update.dart';
import 'package:flutter/foundation.dart';

enum UpdateStatus { idle, checking, updateAvailable, updateDownloaded, error }

class InAppUpdateService {
  UpdateStatus _status = UpdateStatus.idle;
  UpdateStatus get status => _status;

  AppUpdateInfo? _updateInfo;
  AppUpdateInfo? get updateInfo => _updateInfo;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  bool get _isAndroidRelease => Platform.isAndroid && kReleaseMode;

  Future<void> checkForUpdate() async {
    if (!_isAndroidRelease) {
      _status = UpdateStatus.idle;
      return;
    }

    _status = UpdateStatus.checking;
    _errorMessage = null;

    try {
      final updateInfo = await InAppUpdate.checkForUpdate();
      _updateInfo = updateInfo;

      if (updateInfo.updateAvailability == UpdateAvailability.updateAvailable) {
        _status = UpdateStatus.updateAvailable;
      } else {
        _status = UpdateStatus.idle;
      }
    } catch (e) {
      _status = UpdateStatus.error;
      _errorMessage = e.toString();
      if (kDebugMode) {
        print('InAppUpdate checkForUpdate error: $e');
      }
    }
  }

  Future<void> startFlexibleUpdate() async {
    if (!_isAndroidRelease || _updateInfo == null) return;

    try {
      await InAppUpdate.startFlexibleUpdate();
      _status = UpdateStatus.updateDownloaded;
    } catch (e) {
      _status = UpdateStatus.error;
      _errorMessage = e.toString();
      if (kDebugMode) {
        print('InAppUpdate startFlexibleUpdate error: $e');
      }
    }
  }

  Future<void> completeFlexibleUpdate() async {
    if (!_isAndroidRelease) return;

    try {
      await InAppUpdate.completeFlexibleUpdate();
      _status = UpdateStatus.idle;
    } catch (e) {
      _status = UpdateStatus.error;
      _errorMessage = e.toString();
      if (kDebugMode) {
        print('InAppUpdate completeFlexibleUpdate error: $e');
      }
    }
  }

  Future<void> performImmediateUpdate() async {
    if (!_isAndroidRelease || _updateInfo == null) return;

    try {
      await InAppUpdate.performImmediateUpdate();
      _status = UpdateStatus.idle;
    } catch (e) {
      _status = UpdateStatus.error;
      _errorMessage = e.toString();
      if (kDebugMode) {
        print('InAppUpdate performImmediateUpdate error: $e');
      }
    }
  }
}
