import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../services/download_notification_service.dart';
import '../services/ssh_service.dart';
import '../services/download_manager.dart';
import '../services/connection_manager.dart';
import 'ssh_provider.dart';

class SftpItem {
  final String name;
  final String path;
  final bool isDirectory;
  final int? size;
  final DateTime? modified;
  final SftpName sftpName;

  SftpItem({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.size,
    this.modified,
    required this.sftpName,
  });

  String get extension {
    if (isDirectory) return '';
    final parts = name.split('.');
    return parts.length > 1 ? parts.last : '';
  }

  String get formattedSize {
    if (size == null) return '';
    if (size! < 1024) return '$size B';
    if (size! < 1024 * 1024) return '${(size! / 1024).toStringAsFixed(1)} KB';
    if (size! < 1024 * 1024 * 1024) {
      return '${(size! / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size! / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

class SftpBookmark {
  final String name;
  final String path;
  final DateTime createdAt;

  SftpBookmark({required this.name, required this.path, DateTime? createdAt})
    : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'name': name,
    'path': path,
    'createdAt': createdAt.toIso8601String(),
  };

  factory SftpBookmark.fromJson(Map<String, dynamic> json) => SftpBookmark(
    name: json['name'] as String,
    path: json['path'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}

class SftpState {
  final bool isConnected;
  final bool isConnecting;
  final bool isReconnecting;
  final String currentPath;
  final List<SftpItem> items;
  final bool isLoading;
  final String? error;
  final double uploadProgress;
  final double downloadProgress;
  final String? currentOperation;
  final int retryAttempt;
  final Duration? nextRetryDelay;
  final String searchQuery;
  final SftpSortBy sortBy;
  final SftpSortOrder sortOrder;
  final bool showHiddenFiles;
  final bool isSelectionMode;
  final Set<String> selectedPaths;
  final List<SftpBookmark> bookmarks;

  const SftpState({
    this.isConnected = false,
    this.isConnecting = false,
    this.isReconnecting = false,
    this.currentPath = '',
    this.items = const [],
    this.isLoading = false,
    this.error,
    this.uploadProgress = 0.0,
    this.downloadProgress = 0.0,
    this.currentOperation,
    this.retryAttempt = 0,
    this.nextRetryDelay,
    this.searchQuery = '',
    this.sortBy = SftpSortBy.name,
    this.sortOrder = SftpSortOrder.asc,
    this.showHiddenFiles = true,
    this.isSelectionMode = false,
    this.selectedPaths = const {},
    this.bookmarks = const [],
  });

  SftpState copyWith({
    bool? isConnected,
    bool? isConnecting,
    bool? isReconnecting,
    String? currentPath,
    List<SftpItem>? items,
    bool? isLoading,
    String? error,
    double? uploadProgress,
    double? downloadProgress,
    String? currentOperation,
    int? retryAttempt,
    Duration? nextRetryDelay,
    String? searchQuery,
    SftpSortBy? sortBy,
    SftpSortOrder? sortOrder,
    bool? showHiddenFiles,
    bool? isSelectionMode,
    Set<String>? selectedPaths,
    List<SftpBookmark>? bookmarks,
  }) {
    return SftpState(
      isConnected: isConnected ?? this.isConnected,
      isConnecting: isConnecting ?? this.isConnecting,
      isReconnecting: isReconnecting ?? this.isReconnecting,
      currentPath: currentPath ?? this.currentPath,
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      currentOperation: currentOperation,
      retryAttempt: retryAttempt ?? this.retryAttempt,
      nextRetryDelay: nextRetryDelay,
      searchQuery: searchQuery ?? this.searchQuery,
      sortBy: sortBy ?? this.sortBy,
      sortOrder: sortOrder ?? this.sortOrder,
      showHiddenFiles: showHiddenFiles ?? this.showHiddenFiles,
      isSelectionMode: isSelectionMode ?? this.isSelectionMode,
      selectedPaths: selectedPaths ?? this.selectedPaths,
      bookmarks: bookmarks ?? this.bookmarks,
    );
  }

  List<SftpItem> get filteredItems {
    var result = items.where((item) {
      if (!showHiddenFiles && item.name.startsWith('.')) {
        return false;
      }
      if (searchQuery.isNotEmpty) {
        return item.name.toLowerCase().contains(searchQuery.toLowerCase());
      }
      return true;
    }).toList();

    result.sort((a, b) {
      int comparison;
      switch (sortBy) {
        case SftpSortBy.name:
          comparison = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          break;
        case SftpSortBy.size:
          comparison = (a.size ?? 0).compareTo(b.size ?? 0);
          break;
        case SftpSortBy.modified:
          comparison = (a.modified ?? DateTime(1970)).compareTo(
            b.modified ?? DateTime(1970),
          );
          break;
      }
      return sortOrder == SftpSortOrder.asc ? comparison : -comparison;
    });

    final dirs = result.where((i) => i.isDirectory).toList();
    final files = result.where((i) => !i.isDirectory).toList();
    return [...dirs, ...files];
  }

  List<String> get pathSegments {
    if (currentPath.isEmpty) return [];
    final parts = currentPath.split('/').where((s) => s.isNotEmpty).toList();
    return parts;
  }
}

enum SftpSortBy { name, size, modified }

enum SftpSortOrder { asc, desc }

class SftpNotifier extends StateNotifier<SftpState> {
  final SshService _sshService;
  final DownloadManager _downloadManager;
  String _savedPath = '';
  ExponentialBackoff? _backoff;
  Timer? _retryTimer;

  SftpNotifier(this._sshService)
    : _downloadManager = DownloadManager(),
      super(const SftpState());

  String get savedPath => _savedPath;

  void saveCurrentPath() {
    _savedPath = state.currentPath;
  }

  Future<bool> isConnectionAlive() async {
    try {
      if (!_sshService.isConnected) return false;
      await _sshService.checkSftpConnection();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> connect(
    String workingDirectory, {
    bool isReconnect = false,
  }) async {
    if (isReconnect) {
      state = state.copyWith(isReconnecting: true, error: null);
    } else {
      state = state.copyWith(isConnecting: true, error: null);
    }

    _backoff = ExponentialBackoff(
      config: const RetryConfig(
        maxRetries: 5,
        baseDelay: Duration(seconds: 1),
        maxDelay: Duration(seconds: 30),
      ),
    );

    try {
      await _connectWithRetry(workingDirectory);
    } catch (e) {
      state = state.copyWith(
        isConnecting: false,
        isReconnecting: false,
        error: 'Failed to connect: $e',
      );
    }
  }

  Future<void> _connectWithRetry(String workingDirectory) async {
    while (_backoff!.hasMoreRetries) {
      try {
        final homeDir = await _sshService.getHomeDirectory();
        final targetPath = workingDirectory.isNotEmpty
            ? workingDirectory
            : homeDir;

        await _sshService.getSftp();
        await refresh(targetPath);

        state = state.copyWith(
          isConnected: true,
          isConnecting: false,
          isReconnecting: false,
          currentPath: targetPath,
          retryAttempt: 0,
          nextRetryDelay: null,
        );
        return;
      } catch (e) {
        _backoff!.recordAttempt();

        if (!_backoff!.hasMoreRetries) {
          state = state.copyWith(
            isConnecting: false,
            isReconnecting: false,
            error:
                'Failed to connect after ${_backoff!.currentAttempt} attempts: $e',
          );
          return;
        }

        final delay = _backoff!.nextDelay;
        state = state.copyWith(
          retryAttempt: _backoff!.currentAttempt,
          nextRetryDelay: delay,
          error: 'Connection failed. Retrying in ${delay.inSeconds}s...',
        );

        await Future.delayed(delay);
      }
    }
  }

  Future<void> reconnectIfNeeded(String workingDirectory) async {
    final isAlive = await isConnectionAlive();

    if (!isAlive) {
      await connect(workingDirectory, isReconnect: true);
    } else {
      final targetPath = _savedPath.isNotEmpty ? _savedPath : workingDirectory;
      if (targetPath.isNotEmpty && targetPath != state.currentPath) {
        await refresh(targetPath);
      }
    }
  }

  Future<void> retry() async {
    if (state.error == null) return;
    final targetPath = _savedPath.isNotEmpty ? _savedPath : '/';
    await connect(targetPath, isReconnect: true);
  }

  Future<void> refresh([String? path]) async {
    final targetPath = path ?? state.currentPath;
    if (targetPath.isEmpty) return;

    state = state.copyWith(isLoading: true, error: null);

    try {
      final sftpItems = await _sshService.listDirectory(targetPath);
      final items = sftpItems
          .where((item) => item.filename != '.' && item.filename != '..')
          .map((item) => _parseSftpItem(item, targetPath))
          .toList();

      items.sort((a, b) {
        if (a.isDirectory && !b.isDirectory) return -1;
        if (!a.isDirectory && b.isDirectory) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      state = state.copyWith(
        items: items,
        currentPath: targetPath,
        isLoading: false,
        isConnected: true,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to list directory: $e',
      );
    }
  }

  SftpItem _parseSftpItem(SftpName sftpName, String parentPath) {
    final attrs = sftpName.attr;
    final isDir = attrs.isDirectory;
    final path = parentPath == '/'
        ? '/${sftpName.filename}'
        : '$parentPath/${sftpName.filename}';

    return SftpItem(
      name: sftpName.filename,
      path: path,
      isDirectory: isDir,
      size: attrs.size,
      modified: attrs.modifyTime != null
          ? DateTime.fromMillisecondsSinceEpoch(attrs.modifyTime! * 1000)
          : null,
      sftpName: sftpName,
    );
  }

  Future<void> navigateTo(String path) async {
    await refresh(path);
  }

  Future<void> navigateUp() async {
    if (state.currentPath == '/' || state.currentPath.isEmpty) return;

    final parentPath = p.dirname(state.currentPath);
    if (parentPath == state.currentPath) return;

    await refresh(parentPath.isEmpty ? '/' : parentPath);
  }

  Future<void> navigateToSegment(int index) async {
    final segments = state.pathSegments;
    if (index < 0 || index >= segments.length) return;

    final targetPath = '/${segments.take(index + 1).join('/')}';
    await refresh(targetPath);
  }

  Future<void> navigateToHome() async {
    try {
      final homeDir = await _sshService.getHomeDirectory();
      await refresh(homeDir);
    } catch (e) {
      state = state.copyWith(error: 'Failed to get home directory: $e');
    }
  }

  Future<void> createFolder(String name) async {
    if (name.isEmpty) return;

    final newPath = state.currentPath == '/'
        ? '/$name'
        : '${state.currentPath}/$name';

    state = state.copyWith(isLoading: true, error: null);

    try {
      await _sshService.createDirectory(newPath);
      await refresh();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to create folder: $e',
      );
    }
  }

  Future<void> delete(SftpItem item) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      await _sshService.delete(item.path, recursive: item.isDirectory);
      _lastDeletedItem = item;
      _deleteTime = DateTime.now();
      await refresh();
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Failed to delete: $e');
    }
  }

  SftpItem? _lastDeletedItem;
  DateTime? _deleteTime;
  Timer? _undoTimer;

  SftpItem? get lastDeletedItem => _lastDeletedItem;

  bool canUndoDelete() {
    if (_lastDeletedItem == null || _deleteTime == null) return false;
    return DateTime.now().difference(_deleteTime!) < const Duration(seconds: 5);
  }

  Future<void> undoDelete() async {
    state = state.copyWith(isLoading: true, error: null);
    _lastDeletedItem = null;
    _deleteTime = null;
    _undoTimer?.cancel();

    // Since we can't restore deleted files, just refresh
    // In a real implementation, we'd move to trash first
    await refresh();
    state = state.copyWith(isLoading: false);
  }

  void clearUndoState() {
    _lastDeletedItem = null;
    _deleteTime = null;
    _undoTimer?.cancel();
  }

  Future<void> rename(SftpItem item, String newName) async {
    final newPath = state.currentPath == '/'
        ? '/$newName'
        : '${state.currentPath}/$newName';

    state = state.copyWith(isLoading: true, error: null);

    try {
      await _sshService.rename(item.path, newPath);
      await refresh();
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Failed to rename: $e');
    }
  }

  Future<void> downloadFile(SftpItem item, String localPath) async {
    final notificationService = DownloadNotificationService();

    state = state.copyWith(
      downloadProgress: 0.0,
      currentOperation: 'Downloading ${item.name}',
      error: null,
    );

    await notificationService.showDownloadStart(item.name);

    final completer = Completer<void>();

    try {
      final resumeInfo = await _downloadManager.checkResumeCapability(
        sshService: _sshService,
        remotePath: item.path,
        localPath: localPath,
      );

      Timer.run(() async {
        try {
          await _sshService.downloadFile(
            item.path,
            localPath,
            resumeOffset: resumeInfo?.localSize,
            onProgress: (received, total) {
              if (total > 0) {
                final progress = received / total;
                state = state.copyWith(downloadProgress: progress);

                notificationService.updateDownloadProgress(
                  item.name,
                  received,
                  total,
                );
              }
            },
          );

          state = state.copyWith(downloadProgress: 1.0, currentOperation: null);
          await notificationService.showDownloadComplete(item.name, localPath);
          completer.complete();
        } catch (e) {
          completer.completeError(e);
        }
      });

      await completer.future;
    } catch (e) {
      state = state.copyWith(
        error: 'Failed to download: $e',
        currentOperation: null,
      );
      await notificationService.showDownloadError(item.name, e.toString());
    }
  }

  Future<void> uploadFile(String localPath) async {
    final fileName = p.basename(localPath);
    final remotePath = state.currentPath == '/'
        ? '/$fileName'
        : '${state.currentPath}/$fileName';
    await uploadFileTo(localPath, remotePath);
  }

  Future<void> uploadFileTo(String localPath, String remotePath) async {
    final fileName = p.basename(localPath);

    state = state.copyWith(
      uploadProgress: 0.0,
      currentOperation: 'Uploading $fileName',
      error: null,
    );

    try {
      await _sshService.uploadFile(
        localPath,
        remotePath,
        onProgress: (sent, total) {
          if (total > 0) {
            state = state.copyWith(uploadProgress: sent / total);
          }
        },
      );
      state = state.copyWith(uploadProgress: 1.0, currentOperation: null);
      await refresh();
    } catch (e) {
      state = state.copyWith(
        error: 'Failed to upload: $e',
        currentOperation: null,
      );
    }
  }

  void clearError() {
    state = state.copyWith(error: null);
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void setSortBy(SftpSortBy sortBy) {
    state = state.copyWith(sortBy: sortBy);
  }

  void toggleSortOrder() {
    state = state.copyWith(
      sortOrder: state.sortOrder == SftpSortOrder.asc
          ? SftpSortOrder.desc
          : SftpSortOrder.asc,
    );
  }

  void toggleShowHiddenFiles() {
    state = state.copyWith(showHiddenFiles: !state.showHiddenFiles);
  }

  void toggleSelectionMode() {
    state = state.copyWith(
      isSelectionMode: !state.isSelectionMode,
      selectedPaths: {},
    );
  }

  void toggleItemSelection(SftpItem item) {
    final newSelection = Set<String>.from(state.selectedPaths);
    if (newSelection.contains(item.path)) {
      newSelection.remove(item.path);
    } else {
      newSelection.add(item.path);
    }
    state = state.copyWith(selectedPaths: newSelection);
  }

  void selectAllItems() {
    final allPaths = state.filteredItems.map((i) => i.path).toSet();
    state = state.copyWith(selectedPaths: allPaths);
  }

  void clearSelection() {
    state = state.copyWith(selectedPaths: {});
  }

  Future<void> deleteSelected() async {
    final selectedItems = state.items
        .where((i) => state.selectedPaths.contains(i.path))
        .toList();

    state = state.copyWith(isLoading: true, error: null);

    try {
      for (final item in selectedItems) {
        await _sshService.delete(item.path, recursive: item.isDirectory);
      }
      state = state.copyWith(
        isLoading: false,
        isSelectionMode: false,
        selectedPaths: {},
      );
      await refresh();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to delete selected: $e',
      );
    }
  }

  void addBookmark(String name, String path) {
    final bookmarks = List<SftpBookmark>.from(state.bookmarks);
    if (!bookmarks.any((b) => b.path == path)) {
      bookmarks.add(SftpBookmark(name: name, path: path));
      state = state.copyWith(bookmarks: bookmarks);
    }
  }

  void removeBookmark(String path) {
    final bookmarks = state.bookmarks.where((b) => b.path != path).toList();
    state = state.copyWith(bookmarks: bookmarks);
  }

  Future<void> navigateToBookmark(SftpBookmark bookmark) async {
    await refresh(bookmark.path);
  }

  void disconnect() {
    _retryTimer?.cancel();
    state = const SftpState();
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }
}

final sftpProvider = StateNotifierProvider<SftpNotifier, SftpState>((ref) {
  final service = ref.watch(sshServiceProvider);
  return SftpNotifier(service);
});
