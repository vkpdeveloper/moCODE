import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../constants/file_icons.dart';
import '../providers/sftp_provider.dart';
import '../providers/ssh_provider.dart';
import '../services/storage_permission_service.dart';
import '../theme/app_theme.dart';

class SftpBottomSheet extends ConsumerStatefulWidget {
  final String workingDirectory;

  const SftpBottomSheet({super.key, required this.workingDirectory});

  @override
  ConsumerState<SftpBottomSheet> createState() => _SftpBottomSheetState();
}

class _SftpBottomSheetState extends ConsumerState<SftpBottomSheet>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeSftp();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      ref.read(sftpProvider.notifier).saveCurrentPath();
    } else if (state == AppLifecycleState.resumed) {
      _handleAppResume();
    }
  }

  void _initializeSftp() {
    final sshState = ref.read(sshProvider);
    if (sshState.isConnected) {
      ref.read(sftpProvider.notifier).connect(widget.workingDirectory);
    }
  }

  Future<void> _handleAppResume() async {
    final sshState = ref.read(sshProvider);
    if (sshState.isConnected) {
      await ref
          .read(sftpProvider.notifier)
          .reconnectIfNeeded(widget.workingDirectory);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sftpState = ref.watch(sftpProvider);
    final sshState = ref.watch(sshProvider);

    return Container(
      height: double.infinity,
      decoration: const BoxDecoration(color: AppTheme.background),
      child: SafeArea(
        top: true,
        bottom: true,
        child: Column(
          children: [
            _buildHeader(sftpState, sshState),
            _buildBreadcrumb(sftpState),
            Expanded(child: _buildContent(sftpState, sshState)),
            _buildToolbar(sftpState),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(SftpState sftpState, SshState sshState) {
    final isConnected = sftpState.isConnected || sshState.isConnected;
    final isReconnecting = sftpState.isReconnecting;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          const Text(
            'SFTP',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          Container(
            padding: EdgeInsets.all(isConnected ? 4 : 4),
            decoration: BoxDecoration(
              color: _getStatusColor(
                isConnected,
                isReconnecting,
              ).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(isConnected ? 50 : 4),
            ),
            child: isConnected
                ? Icon(
                    Icons.check,
                    size: 14,
                    color: _getStatusColor(isConnected, isReconnecting),
                  )
                : Text(
                    _getStatusText(isConnected, isReconnecting),
                    style: TextStyle(
                      color: _getStatusColor(isConnected, isReconnecting),
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
          ),
          const SizedBox(width: 8),
          if (sftpState.downloadProgress > 0 && sftpState.downloadProgress < 1)
            SizedBox(
              width: 24,
              height: 24,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: sftpState.downloadProgress,
                    strokeWidth: 2,
                    backgroundColor: AppTheme.surfaceVariant,
                    valueColor: const AlwaysStoppedAnimation(AppTheme.info),
                  ),
                  const Icon(Icons.download, size: 12, color: AppTheme.info),
                ],
              ),
            )
          else
            IconButton(
              onPressed: sftpState.isReconnecting
                  ? null
                  : () => ref.read(sftpProvider.notifier).refresh(),
              icon: const Icon(
                Icons.refresh,
                size: 18,
                color: AppTheme.textSecondary,
              ),
              tooltip: 'Refresh',
            ),
          if (!isConnected && sshState.credentials != null && !isReconnecting)
            IconButton(
              onPressed: () {
                ref.read(sftpProvider.notifier).retry();
              },
              icon: const Icon(
                Icons.wifi_off,
                size: 18,
                color: AppTheme.accent,
              ),
              tooltip: 'Reconnect',
            ),
          IconButton(
            onPressed: () {
              ref.read(sftpProvider.notifier).disconnect();
              Navigator.of(context).pop();
            },
            icon: const Icon(
              Icons.close,
              size: 18,
              color: AppTheme.textSecondary,
            ),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(bool isConnected, bool isReconnecting) {
    if (isReconnecting) return AppTheme.warning;
    if (isConnected) return AppTheme.success;
    return AppTheme.error;
  }

  String _getStatusText(bool isConnected, bool isReconnecting) {
    if (isReconnecting) return 'Reconnecting';
    if (isConnected) return 'Connected';
    return 'Disconnected';
  }

  Widget _buildBreadcrumb(SftpState sftpState) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 28,
            child: Row(
              children: [
                InkWell(
                  onTap: () => ref.read(sftpProvider.notifier).navigateToHome(),
                  borderRadius: BorderRadius.circular(4),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Icon(
                      Icons.home,
                      size: 16,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
                if (sftpState.currentPath.isNotEmpty &&
                    sftpState.currentPath != '/')
                  const Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: AppTheme.textTertiary,
                  ),
                Expanded(
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: sftpState.pathSegments.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) return const SizedBox.shrink();
                      final isLast = index == sftpState.pathSegments.length;
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          InkWell(
                            onTap: isLast
                                ? null
                                : () => ref
                                      .read(sftpProvider.notifier)
                                      .navigateToSegment(index - 1),
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                              child: Text(
                                sftpState.pathSegments[index - 1],
                                style: TextStyle(
                                  color: isLast
                                      ? AppTheme.accent
                                      : AppTheme.textSecondary,
                                  fontSize: 12,
                                  fontWeight: isLast
                                      ? FontWeight.w500
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                          ),
                          if (!isLast)
                            const Icon(
                              Icons.chevron_right,
                              size: 14,
                              color: AppTheme.textTertiary,
                            ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    ref.read(sftpProvider.notifier).toggleShowHiddenFiles();
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      sftpState.showHiddenFiles
                          ? Icons.visibility
                          : Icons.visibility_off,
                      size: 16,
                      color: sftpState.showHiddenFiles
                          ? AppTheme.accent
                          : AppTheme.textTertiary,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    _showBookmarks(context, sftpState);
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      sftpState.bookmarks.isNotEmpty
                          ? Icons.bookmark
                          : Icons.bookmark_border,
                      size: 16,
                      color: sftpState.bookmarks.isNotEmpty
                          ? AppTheme.accent
                          : AppTheme.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    _showSortOptions(context, sftpState);
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.sort,
                      size: 16,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: 32,
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppTheme.border),
            ),
            child: TextField(
              onChanged: (value) =>
                  ref.read(sftpProvider.notifier).setSearchQuery(value),
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
              decoration: const InputDecoration(
                hintText: 'Search files...',
                hintStyle: TextStyle(
                  color: AppTheme.textTertiary,
                  fontSize: 12,
                ),
                prefixIcon: Icon(
                  Icons.search,
                  size: 16,
                  color: AppTheme.textTertiary,
                ),
                prefixIconConstraints: BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSortOptions(BuildContext context, SftpState sftpState) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 3,
              color: AppTheme.border,
              margin: const EdgeInsets.only(top: 8, bottom: 16),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Sort by',
                  style: TextStyle(
                    color: AppTheme.textTertiary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            ...SftpSortBy.values.map((sortBy) {
              final label = switch (sortBy) {
                SftpSortBy.name => 'Name',
                SftpSortBy.size => 'Size',
                SftpSortBy.modified => 'Modified',
              };
              final isSelected = sftpState.sortBy == sortBy;
              return ListTile(
                leading: Icon(
                  isSelected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  size: 20,
                  color: isSelected ? AppTheme.accent : AppTheme.textTertiary,
                ),
                title: Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? AppTheme.accent : AppTheme.textPrimary,
                    fontSize: 14,
                  ),
                ),
                onTap: () {
                  HapticFeedback.lightImpact();
                  ref.read(sftpProvider.notifier).setSortBy(sortBy);
                  Navigator.pop(ctx);
                },
              );
            }),
            const Divider(color: AppTheme.border, height: 1),
            ListTile(
              leading: Icon(
                sftpState.sortOrder == SftpSortOrder.asc
                    ? Icons.arrow_upward
                    : Icons.arrow_downward,
                size: 20,
                color: AppTheme.textSecondary,
              ),
              title: Text(
                sftpState.sortOrder == SftpSortOrder.asc
                    ? 'Ascending'
                    : 'Descending',
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                ),
              ),
              trailing: const Icon(
                Icons.swap_vert,
                size: 20,
                color: AppTheme.textSecondary,
              ),
              onTap: () {
                HapticFeedback.lightImpact();
                ref.read(sftpProvider.notifier).toggleSortOrder();
                Navigator.pop(ctx);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showBookmarks(BuildContext context, SftpState sftpState) {
    final isCurrentPathBookmarked = sftpState.bookmarks.any(
      (b) => b.path == sftpState.currentPath,
    );

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 3,
              color: AppTheme.border,
              margin: const EdgeInsets.only(top: 8, bottom: 16),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Bookmarks',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: isCurrentPathBookmarked
                        ? null
                        : () {
                            HapticFeedback.lightImpact();
                            ref
                                .read(sftpProvider.notifier)
                                .addBookmark(
                                  sftpState.currentPath.split('/').lastOrNull ??
                                      'Root',
                                  sftpState.currentPath,
                                );
                            Navigator.pop(ctx);
                          },
                    icon: Icon(
                      Icons.add,
                      size: 18,
                      color: isCurrentPathBookmarked
                          ? AppTheme.textTertiary
                          : AppTheme.accent,
                    ),
                    label: Text(
                      'Add Current',
                      style: TextStyle(
                        color: isCurrentPathBookmarked
                            ? AppTheme.textTertiary
                            : AppTheme.accent,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (sftpState.bookmarks.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(
                      Icons.bookmark_border,
                      size: 48,
                      color: AppTheme.textTertiary,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'No bookmarks yet',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Add the current folder to quickly access it later',
                      style: TextStyle(
                        color: AppTheme.textTertiary,
                        fontSize: 11,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            else
              ...sftpState.bookmarks.map((bookmark) {
                return ListTile(
                  leading: const Icon(
                    Icons.folder,
                    size: 20,
                    color: AppTheme.warning,
                  ),
                  title: Text(
                    bookmark.name,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 14,
                    ),
                  ),
                  subtitle: Text(
                    bookmark.path,
                    style: const TextStyle(
                      color: AppTheme.textTertiary,
                      fontSize: 10,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: InkWell(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      ref
                          .read(sftpProvider.notifier)
                          .removeBookmark(bookmark.path);
                      Navigator.pop(ctx);
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(
                        Icons.close,
                        size: 18,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                  ),
                  onTap: () {
                    HapticFeedback.lightImpact();
                    ref
                        .read(sftpProvider.notifier)
                        .navigateToBookmark(bookmark);
                    Navigator.pop(ctx);
                  },
                );
              }),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(SftpState sftpState, SshState sshState) {
    if (sftpState.isReconnecting) {
      return _buildReconnectingOverlay(sftpState);
    }

    if (sftpState.isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppTheme.accent,
          strokeWidth: 2,
        ),
      );
    }

    if (sftpState.error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppTheme.error),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                sftpState.error!,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            if (sshState.credentials != null)
              OutlinedButton(
                onPressed: () => ref.read(sftpProvider.notifier).retry(),
                child: const Text('RETRY'),
              ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => ref.read(sftpProvider.notifier).clearError(),
              child: const Text('DISMISS'),
            ),
          ],
        ),
      );
    }

    if (sftpState.items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.folder_open,
              size: 48,
              color: AppTheme.textTertiary,
            ),
            const SizedBox(height: 16),
            const Text(
              'No files',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            ),
          ],
        ),
      );
    }

    final filteredItems = sftpState.filteredItems;

    if (filteredItems.isEmpty && sftpState.searchQuery.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.search_off,
              size: 48,
              color: AppTheme.textTertiary,
            ),
            const SizedBox(height: 16),
            Text(
              'No files matching "${sftpState.searchQuery}"',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppTheme.accent,
      backgroundColor: AppTheme.surface,
      onRefresh: () => ref.read(sftpProvider.notifier).refresh(),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: filteredItems.length,
        itemBuilder: (context, index) {
          final item = filteredItems[index];
          final isSelected = sftpState.selectedPaths.contains(item.path);
          return _SftpListItem(
            item: item,
            isSelected: isSelected,
            isSelectionMode: sftpState.isSelectionMode,
            onTap: () {
              if (sftpState.isSelectionMode) {
                HapticFeedback.selectionClick();
                ref.read(sftpProvider.notifier).toggleItemSelection(item);
              } else if (item.isDirectory) {
                ref.read(sftpProvider.notifier).navigateTo(item.path);
              }
            },
            onLongPress: () {
              if (!sftpState.isSelectionMode) {
                HapticFeedback.mediumImpact();
                ref.read(sftpProvider.notifier).toggleSelectionMode();
                ref.read(sftpProvider.notifier).toggleItemSelection(item);
              }
            },
          );
        },
      ),
    );
  }

  Widget _buildReconnectingOverlay(SftpState sftpState) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.warning),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Reconnecting to SFTP...',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          if (sftpState.nextRetryDelay != null)
            Text(
              'Retry ${sftpState.retryAttempt}/5 in ${sftpState.nextRetryDelay!.inSeconds}s',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
              ),
            ),
          const SizedBox(height: 24),
          TextButton(
            onPressed: () => ref.read(sftpProvider.notifier).retry(),
            child: const Text(
              'Retry Now',
              style: TextStyle(
                color: AppTheme.accent,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(SftpState sftpState) {
    final isOperating = sftpState.currentOperation != null;

    if (sftpState.isSelectionMode) {
      return _buildSelectionModeToolbar(sftpState);
    }

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          _ToolbarButton(
            icon: Icons.create_new_folder_outlined,
            label: 'New Folder',
            onPressed: isOperating
                ? null
                : () {
                    HapticFeedback.lightImpact();
                    _showNewFolderDialog(context);
                  },
          ),
          _ToolbarButton(
            icon: Icons.upload_file,
            label: 'Upload',
            onPressed: isOperating
                ? null
                : () {
                    HapticFeedback.lightImpact();
                    _uploadFile();
                  },
          ),
          _ToolbarButton(
            icon: Icons.arrow_upward,
            label: 'Parent',
            onPressed: isOperating || sftpState.currentPath == '/'
                ? null
                : () {
                    HapticFeedback.lightImpact();
                    ref.read(sftpProvider.notifier).navigateUp();
                  },
          ),
          const Spacer(),
          if (sftpState.uploadProgress > 0 && sftpState.uploadProgress < 1)
            SizedBox(
              width: 100,
              child: LinearProgressIndicator(
                value: sftpState.uploadProgress,
                backgroundColor: AppTheme.surfaceVariant,
                valueColor: const AlwaysStoppedAnimation(AppTheme.accent),
              ),
            ),
          if (sftpState.currentOperation != null)
            Text(
              sftpState.currentOperation!,
              style: const TextStyle(
                color: AppTheme.textTertiary,
                fontSize: 11,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSelectionModeToolbar(SftpState sftpState) {
    final selectedCount = sftpState.selectedPaths.length;
    final hasSelection = selectedCount > 0;

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          TextButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              ref.read(sftpProvider.notifier).toggleSelectionMode();
            },
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$selectedCount selected',
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: hasSelection
                ? () {
                    HapticFeedback.lightImpact();
                    ref.read(sftpProvider.notifier).selectAllItems();
                  }
                : null,
            child: Text(
              'All',
              style: TextStyle(
                color: hasSelection ? AppTheme.accent : AppTheme.textTertiary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: hasSelection
                ? () {
                    HapticFeedback.heavyImpact();
                    _confirmDeleteSelected(context);
                  }
                : null,
            icon: Icon(
              Icons.delete,
              size: 20,
              color: hasSelection ? AppTheme.error : AppTheme.textTertiary,
            ),
            tooltip: 'Delete selected',
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: hasSelection
                ? () {
                    HapticFeedback.lightImpact();
                    _downloadSelected(context);
                  }
                : null,
            icon: Icon(
              Icons.download,
              size: 20,
              color: hasSelection
                  ? AppTheme.textPrimary
                  : AppTheme.textTertiary,
            ),
            tooltip: 'Download selected',
          ),
        ],
      ),
    );
  }

  void _confirmDeleteSelected(BuildContext context) {
    final selectedCount = ref.read(sftpProvider).selectedPaths.length;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text(
          'Delete Selected',
          style: TextStyle(color: AppTheme.textPrimary, fontSize: 16),
        ),
        content: Text(
          'Are you sure you want to delete $selectedCount item(s)?\n\nThis action cannot be undone.',
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(sftpProvider.notifier).deleteSelected();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showNewFolderDialog(BuildContext context) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text(
          'New Folder',
          style: TextStyle(color: AppTheme.textPrimary, fontSize: 16),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            hintText: 'Folder name',
            hintStyle: const TextStyle(color: AppTheme.textTertiary),
            filled: true,
            fillColor: AppTheme.background,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: const BorderSide(color: AppTheme.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: const BorderSide(color: AppTheme.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: const BorderSide(color: AppTheme.accent),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                ref.read(sftpProvider.notifier).createFolder(controller.text);
                Navigator.pop(ctx);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _uploadFile() async {
    try {
      final result = await FilePicker.platform.pickFiles();
      if (result != null && result.files.single.path != null) {
        final localPath = result.files.single.path!;
        final fileName = p.basename(localPath);
        final currentPath = ref.read(sftpProvider).currentPath;
        final remotePath = currentPath == '/'
            ? '/$fileName'
            : '$currentPath/$fileName';

        final existingItem = ref
            .read(sftpProvider)
            .items
            .where((i) => i.name == fileName)
            .firstOrNull;
        if (existingItem != null) {
          final action = await _showFileConflictDialog(context, fileName);
          if (action == _FileConflictAction.cancel) {
            return;
          } else if (action == _FileConflictAction.keepBoth) {
            final uniqueName = _generateUniqueName(
              fileName,
              ref.read(sftpProvider).items,
            );
            final uniqueRemotePath = currentPath == '/'
                ? '/$uniqueName'
                : '$currentPath/$uniqueName';
            await ref
                .read(sftpProvider.notifier)
                .uploadFileTo(localPath, uniqueRemotePath);
            return;
          }
        }
        await ref.read(sftpProvider.notifier).uploadFile(localPath);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to upload: $e')));
      }
    }
  }

  String _generateUniqueName(String fileName, List<SftpItem> items) {
    final extension = p.extension(fileName);
    final nameWithoutExt = p.basenameWithoutExtension(fileName);
    int counter = 1;
    final existingNames = items.map((i) => i.name).toSet();

    while (true) {
      final newName = '$nameWithoutExt ($counter)$extension';
      if (!existingNames.contains(newName)) {
        return newName;
      }
      counter++;
    }
  }

  void _showContextMenu(BuildContext context, SftpItem item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        color: AppTheme.surface,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 3,
              color: AppTheme.border,
              margin: const EdgeInsets.only(top: 8, bottom: 16),
            ),
            ListTile(
              leading: const Icon(
                Icons.download,
                color: AppTheme.textSecondary,
                size: 20,
              ),
              title: const Text(
                'Download',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 14),
              ),
              enabled: !item.isDirectory,
              onTap: () async {
                Navigator.pop(ctx);
                HapticFeedback.lightImpact();
                await _downloadFile(item);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.edit,
                color: AppTheme.textSecondary,
                size: 20,
              ),
              title: const Text(
                'Rename',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 14),
              ),
              onTap: () {
                Navigator.pop(ctx);
                HapticFeedback.lightImpact();
                _showRenameDialog(context, item);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.delete,
                color: AppTheme.error,
                size: 20,
              ),
              title: const Text(
                'Delete',
                style: TextStyle(color: AppTheme.error, fontSize: 14),
              ),
              onTap: () {
                Navigator.pop(ctx);
                HapticFeedback.heavyImpact();
                _confirmDelete(context, item);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.copy,
                color: AppTheme.textSecondary,
                size: 20,
              ),
              title: const Text(
                'Copy Path',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 14),
              ),
              onTap: () {
                Navigator.pop(ctx);
                HapticFeedback.selectionClick();
                Clipboard.setData(ClipboardData(text: item.path));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Copied: ${item.path}'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<bool> _downloadFile(SftpItem item, {bool showSnackBars = true}) async {
    try {
      bool hasPermission =
          await StoragePermissionService.checkStoragePermission();
      if (!hasPermission) {
        hasPermission =
            await StoragePermissionService.requestStoragePermission();
      }

      Directory? directory;

      if (hasPermission && Platform.isAndroid) {
        try {
          final downloadsDir = Directory('/storage/emulated/0/Download');
          if (await downloadsDir.exists()) {
            directory = downloadsDir;
          }
        } catch (e) {}
      }

      if (directory == null) {
        directory = await getApplicationDocumentsDirectory();
      }

      String localPath = p.join(directory.path, item.name);

      final existingFile = File(localPath);
      if (await existingFile.exists()) {
        final action = await _showFileConflictDialog(context, item.name);

        if (action == _FileConflictAction.cancel) {
          return false;
        } else if (action == _FileConflictAction.keepBoth) {
          localPath = await _generateUniqueFilePath(directory.path, item.name);
        }
      }

      if (mounted && showSnackBars) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Downloading...'),
            duration: Duration(seconds: 1),
          ),
        );
      }

      await ref.read(sftpProvider.notifier).downloadFile(item, localPath);

      if (mounted && showSnackBars) {
        final displayPath = hasPermission && Platform.isAndroid
            ? 'Downloads folder'
            : 'App documents';
        final fileName = p.basename(localPath);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Downloaded to $displayPath: $fileName'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return true;
    } catch (e) {
      if (mounted) {
        // Always show error snackbar even if showSnackBars is false
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to download: $e')));
      }
      return false;
    }
  }

  Future<String> _generateUniqueFilePath(
    String directoryPath,
    String fileName,
  ) async {
    final extension = p.extension(fileName);
    final nameWithoutExt = p.basenameWithoutExtension(fileName);
    int counter = 1;

    while (true) {
      final newName = '$nameWithoutExt ($counter)$extension';
      final newPath = p.join(directoryPath, newName);
      final file = File(newPath);

      if (!await file.exists()) {
        return newPath;
      }
      counter++;
    }
  }

  Future<_FileConflictAction> _showFileConflictDialog(
    BuildContext context,
    String fileName,
  ) async {
    return await showDialog<_FileConflictAction>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppTheme.surface,
            title: const Text(
              'File Already Exists',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 16),
            ),
            content: Text(
              '"$fileName" already exists in this location. What would you like to do?',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, _FileConflictAction.cancel),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.pop(ctx, _FileConflictAction.keepBoth),
                child: const Text(
                  'Keep Both',
                  style: TextStyle(color: AppTheme.accent),
                ),
              ),
              ElevatedButton(
                onPressed: () =>
                    Navigator.pop(ctx, _FileConflictAction.replace),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Replace'),
              ),
            ],
          ),
        ) ??
        _FileConflictAction.cancel;
  }

  void _showRenameDialog(BuildContext context, SftpItem item) {
    final controller = TextEditingController(text: item.name);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text(
          'Rename',
          style: TextStyle(color: AppTheme.textPrimary, fontSize: 16),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            hintText: 'New name',
            hintStyle: const TextStyle(color: AppTheme.textTertiary),
            filled: true,
            fillColor: AppTheme.background,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: const BorderSide(color: AppTheme.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: const BorderSide(color: AppTheme.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: const BorderSide(color: AppTheme.accent),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.isNotEmpty && controller.text != item.name) {
                ref.read(sftpProvider.notifier).rename(item, controller.text);
                Navigator.pop(ctx);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, SftpItem item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text(
          'Delete',
          style: TextStyle(color: AppTheme.textPrimary, fontSize: 16),
        ),
        content: Text(
          'Are you sure you want to delete "${item.name}"?${item.isDirectory ? '\n\nThis will delete all contents inside.' : ''}',
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(sftpProvider.notifier).delete(item);
              if (mounted) {
                ScaffoldMessenger.of(context).clearSnackBars();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Deleted ${item.name}'),
                    duration: const Duration(seconds: 5),
                    action: SnackBarAction(
                      label: 'Undo',
                      textColor: AppTheme.accent,
                      onPressed: () {
                        ref.read(sftpProvider.notifier).undoDelete();
                      },
                    ),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadSelected(BuildContext context) async {
    final sftpState = ref.read(sftpProvider);
    final selectedItems = sftpState.items
        .where((i) => sftpState.selectedPaths.contains(i.path))
        .toList();

    final filesToDownload = selectedItems.where((i) => !i.isDirectory).toList();
    final skippedCount = selectedItems.length - filesToDownload.length;

    if (filesToDownload.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No files selected to download (directories skipped)',
            ),
          ),
        );
      }
      return;
    }

    int successCount = 0;
    for (final item in filesToDownload) {
      final success = await _downloadFile(item, showSnackBars: false);
      if (success) successCount++;
    }

    if (mounted) {
      ref.read(sftpProvider.notifier).toggleSelectionMode();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Downloaded $successCount files${skippedCount > 0 ? ' ($skippedCount directories skipped)' : ''}',
          ),
        ),
      );
    }
  }
}

enum _FileConflictAction { cancel, replace, keepBoth }

class _SftpListItem extends StatelessWidget {
  final SftpItem item;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback? onSelect;

  const _SftpListItem({
    required this.item,
    required this.onTap,
    required this.onLongPress,
    this.isSelected = false,
    this.isSelectionMode = false,
    this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final icon = item.isDirectory
        ? Icons.folder
        : getIconForExtension(item.extension);

    final iconColor = item.isDirectory ? AppTheme.warning : AppTheme.accent;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.accent.withValues(alpha: 0.1) : null,
          border: const Border(
            bottom: BorderSide(color: AppTheme.border, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            if (isSelectionMode)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Icon(
                  isSelected ? Icons.check_circle : Icons.circle_outlined,
                  color: isSelected ? AppTheme.accent : AppTheme.textTertiary,
                  size: 22,
                ),
              ),
            Icon(icon, color: iconColor, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: GoogleFonts.jetBrainsMono(
                      color: AppTheme.textPrimary,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (item.modified != null || item.size != null)
                    Text(
                      [
                        if (item.formattedSize.isNotEmpty) item.formattedSize,
                        if (item.modified != null) _formatDate(item.modified!),
                      ].join(' • '),
                      style: const TextStyle(
                        color: AppTheme.textTertiary,
                        fontSize: 10,
                      ),
                    ),
                ],
              ),
            ),
            if (item.isDirectory && !isSelectionMode)
              const Icon(
                Icons.chevron_right,
                color: AppTheme.textTertiary,
                size: 18,
              ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  const _ToolbarButton({
    required this.icon,
    required this.label,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(
        icon,
        size: 16,
        color: onPressed != null
            ? AppTheme.textSecondary
            : AppTheme.textTertiary,
      ),
      label: Text(
        label,
        style: TextStyle(
          color: onPressed != null
              ? AppTheme.textSecondary
              : AppTheme.textTertiary,
          fontSize: 11,
        ),
      ),
    );
  }
}

void showSftpBottomSheet(BuildContext context, String workingDirectory) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    isDismissible: false,
    enableDrag: false,
    builder: (context) => SftpBottomSheet(workingDirectory: workingDirectory),
  );
}
