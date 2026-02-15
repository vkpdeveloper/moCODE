import 'dart:async';
import 'dart:io';

import '../services/ssh_service.dart';

class DownloadProgress {
  final String fileName;
  final int received;
  final int total;
  final bool isComplete;
  final String? error;
  final bool isResuming;

  DownloadProgress({
    required this.fileName,
    required this.received,
    required this.total,
    this.isComplete = false,
    this.error,
    this.isResuming = false,
  });
}

class PendingDownload {
  final String remotePath;
  final String localPath;
  final String fileName;
  final DateTime timestamp;

  PendingDownload({
    required this.remotePath,
    required this.localPath,
    required this.fileName,
    required this.timestamp,
  });
}

class DownloadManager {
  static final DownloadManager _instance = DownloadManager._internal();
  factory DownloadManager() => _instance;
  DownloadManager._internal();

  final Map<String, StreamController<DownloadProgress>> _downloads = {};
  final List<PendingDownload> _pendingDownloads = [];

  Stream<DownloadProgress> downloadFile({
    required SshService sshService,
    required String remotePath,
    required String localPath,
    required String fileName,
    int? resumeOffset,
  }) {
    if (_downloads.containsKey(remotePath)) {
      return _downloads[remotePath]!.stream;
    }

    final controller = StreamController<DownloadProgress>.broadcast();
    _downloads[remotePath] = controller;

    _startDownload(
      sshService: sshService,
      remotePath: remotePath,
      localPath: localPath,
      fileName: fileName,
      resumeOffset: resumeOffset,
      controller: controller,
    );

    return controller.stream;
  }

  void _startDownload({
    required SshService sshService,
    required String remotePath,
    required String localPath,
    required String fileName,
    int? resumeOffset,
    required StreamController<DownloadProgress> controller,
  }) {
    try {
      _downloadWithRetry(
        sshService: sshService,
        remotePath: remotePath,
        localPath: localPath,
        fileName: fileName,
        resumeOffset: resumeOffset,
        onProgress: (received, total) {
          controller.add(DownloadProgress(
            fileName: fileName,
            received: received,
            total: total,
            isResuming: resumeOffset != null && resumeOffset > 0,
          ));
        },
        onComplete: () {
          controller.add(DownloadProgress(
            fileName: fileName,
            received: 1,
            total: 1,
            isComplete: true,
          ));
          _removePendingDownload(remotePath);
          _downloads.remove(remotePath);
          controller.close();
        },
        onError: (error) {
          controller.add(DownloadProgress(
            fileName: fileName,
            received: 0,
            total: 0,
            error: error.toString(),
          ));
          _downloads.remove(remotePath);
          controller.close();
        },
      );
    } catch (e) {
      controller.add(DownloadProgress(
        fileName: fileName,
        received: 0,
        total: 0,
        error: e.toString(),
      ));
      _downloads.remove(remotePath);
      controller.close();
    }
  }

  Future<void> _downloadWithRetry({
    required SshService sshService,
    required String remotePath,
    required String localPath,
    required String fileName,
    int? resumeOffset,
    required void Function(int received, int total) onProgress,
    required void Function() onComplete,
    required void Function(dynamic error) onError,
    int maxRetries = 5,
  }) async {
    int attempts = 0;

    while (attempts < maxRetries) {
      try {
        int currentOffset = resumeOffset ?? 0;

        if (currentOffset == 0) {
          final partFile = File('$localPath.part');
          if (await partFile.exists()) {
            currentOffset = await partFile.length();
          }
        }

        await sshService.downloadFile(
          remotePath,
          localPath,
          resumeOffset: currentOffset > 0 ? currentOffset : null,
          onProgress: onProgress,
        );

        final partFile = File('$localPath.part');
        if (await partFile.exists()) {
          await partFile.rename(localPath);
        }

        onComplete();
        return;
      } catch (e) {
        attempts++;

        if (attempts >= maxRetries) {
          onError(e);
          return;
        }

        _addPendingDownload(PendingDownload(
          remotePath: remotePath,
          localPath: localPath,
          fileName: fileName,
          timestamp: DateTime.now(),
        ));

        await Future.delayed(Duration(seconds: attempts * 2));

        final isConnected = await _checkConnection(sshService);
        if (!isConnected) {
          await _waitForConnection(sshService);
        }
      }
    }
  }

  Future<bool> _checkConnection(SshService sshService) async {
    try {
      return sshService.isConnected;
    } catch (e) {
      return false;
    }
  }

  Future<void> _waitForConnection(SshService sshService) async {
    while (!sshService.isConnected) {
      await Future.delayed(const Duration(seconds: 1));
    }
  }

  void _addPendingDownload(PendingDownload download) {
    final existing = _pendingDownloads.indexWhere((d) => d.remotePath == download.remotePath);
    if (existing >= 0) {
      _pendingDownloads[existing] = download;
    } else {
      _pendingDownloads.add(download);
    }
  }

  void _removePendingDownload(String remotePath) {
    _pendingDownloads.removeWhere((d) => d.remotePath == remotePath);
  }

  List<PendingDownload> get pendingDownloads => List.unmodifiable(_pendingDownloads);

  void clearPendingDownloads() {
    _pendingDownloads.clear();
  }

  Future<DownloadResumeInfo?> checkResumeCapability({
    required SshService sshService,
    required String remotePath,
    required String localPath,
  }) async {
    try {
      final partFile = File('$localPath.part');
      if (!await partFile.exists()) {
        return null;
      }

      final localSize = await partFile.length();
      final remoteInfo = await sshService.getRemoteFileInfo(remotePath);

      if (localSize >= remoteInfo.size) {
        await partFile.delete();
        return null;
      }

      return DownloadResumeInfo(
        localSize: localSize,
        remoteSize: remoteInfo.size,
        canResume: true,
      );
    } catch (e) {
      return null;
    }
  }

  Stream<DownloadProgress> resumeDownload({
    required SshService sshService,
    required String remotePath,
    required String localPath,
    required String fileName,
  }) {
    return downloadFile(
      sshService: sshService,
      remotePath: remotePath,
      localPath: localPath,
      fileName: fileName,
    );
  }

  void cancelDownload(String remotePath) {
    _downloads[remotePath]?.close();
    _downloads.remove(remotePath);
    _removePendingDownload(remotePath);
  }
}

class DownloadResumeInfo {
  final int localSize;
  final int remoteSize;
  final bool canResume;

  DownloadResumeInfo({
    required this.localSize,
    required this.remoteSize,
    required this.canResume,
  });

  int get downloadedBytes => localSize;
  int get remainingBytes => remoteSize - localSize;
  double get progress => remoteSize > 0 ? localSize / remoteSize : 0;
}
