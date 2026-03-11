import 'dart:io' show Platform;
import 'package:in_app_update/in_app_update.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

enum UpdateStatus { idle, checking, updateAvailable, updateDownloaded, error }

class InAppUpdateService {
  static const String _androidPackageId = 'com.ordinity.mocode';
  static final Uri _playStoreUri = Uri.parse(
    'market://details?id=$_androidPackageId',
  );
  static final Uri _playStoreWebUri = Uri.parse(
    'https://play.google.com/store/apps/details?id=$_androidPackageId',
  );

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
      } else if (updateInfo.installStatus == InstallStatus.downloaded) {
        _status = UpdateStatus.updateDownloaded;
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
      final info = _updateInfo!;

      if (info.immediateUpdateAllowed) {
        await InAppUpdate.performImmediateUpdate();
        _status = UpdateStatus.idle;
        return;
      }

      if (info.flexibleUpdateAllowed) {
        await InAppUpdate.startFlexibleUpdate();
        _status = UpdateStatus.updateDownloaded;
        return;
      }

      final openedStore = await openPlayStoreListing();
      if (!openedStore) {
        _status = UpdateStatus.error;
        _errorMessage =
            'No supported in-app update type is available for this build.';
      }
    } catch (e) {
      final openedStore = await openPlayStoreListing();
      if (openedStore) {
        _status = UpdateStatus.updateAvailable;
        _errorMessage = null;
        return;
      }
      _status = UpdateStatus.error;
      _errorMessage = e.toString();
      if (kDebugMode) {
        print('InAppUpdate performImmediateUpdate error: $e');
      }
    }
  }

  Future<bool> openPlayStoreListing() async {
    if (!_isAndroidRelease) return false;
    if (await canLaunchUrl(_playStoreUri)) {
      return launchUrl(_playStoreUri, mode: LaunchMode.externalApplication);
    }
    return launchUrl(_playStoreWebUri, mode: LaunchMode.externalApplication);
  }
}
