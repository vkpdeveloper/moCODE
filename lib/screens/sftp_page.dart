import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../constants/file_icons.dart';
import '../providers/sftp_provider.dart';
import '../providers/ssh_provider.dart';
import '../services/storage_permission_service.dart';
import '../theme/app_theme.dart';

class SftpPage extends ConsumerStatefulWidget {
  final String workingDirectory;

  const SftpPage({super.key, required this.workingDirectory});

  @override
  ConsumerState<SftpPage> createState() => _SftpPageState();
}

class _SftpPageState extends ConsumerState<SftpPage>
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
    final sftpState = ref.read(sftpProvider);
    final sshState = ref.read(sshProvider);

    // Smart connection logic:
    // 1. If SFTP is already connected and we are in the requested directory, just refresh.
    // 2. Otherwise, if SSH is connected, establish/re-establish SFTP connection to the requested directory.
    if (sftpState.isConnected &&
        sftpState.currentPath == widget.workingDirectory) {
      ref.read(sftpProvider.notifier).refresh();
    } else if (sshState.isConnected) {
      ref.read(sftpProvider.notifier).connect(widget.workingDirectory);
    }
  }

  Future<void> _handleAppResume() async {
    final isAlive = await ref.read(sftpProvider.notifier).isConnectionAlive();
    if (!isAlive) {
      await ref
          .read(sftpProvider.notifier)
          .reconnectIfNeeded(widget.workingDirectory);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sftpState = ref.watch(sftpProvider);
    final sshState = ref.watch(sshProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: _buildAppBar(context, sftpState, sshState),
      body: SafeArea(
        child: Column(
          children: [
            _buildBreadcrumb(sftpState),
            Expanded(child: _buildContent(sftpState, sshState)),
            // _buildToolbar is now conditionally shown or part of the content
            // The original bottom sheet had a toolbar at the bottom.
            _buildToolbar(sftpState),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    SftpState sftpState,
    SshState sshState,
  ) {
    final isConnected = sftpState.isConnected || sshState.isConnected;
    final isReconnecting = sftpState.isReconnecting;

    return AppBar(
      backgroundColor: AppTheme.surface,
      elevation: 0,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1.0),
        child: Container(color: AppTheme.border, height: 1.0),
      ),
      title: const Text(
        'SFTP',
        style: TextStyle(
          color: AppTheme.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
      actions: [
        Center(
          child: Container(
            padding: EdgeInsets.all(isConnected ? 4 : 4),
            margin: const EdgeInsets.only(right: 8),
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
        ),
        if (sftpState.downloadProgress > 0 && sftpState.downloadProgress < 1)
          SizedBox(
            width: 24,
            height: 24,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  margin: const EdgeInsets.only(right: 16),
                  child: CircularProgressIndicator(
                    value: sftpState.downloadProgress,
                    strokeWidth: 2,
                    backgroundColor: AppTheme.surfaceVariant,
                    valueColor: const AlwaysStoppedAnimation(AppTheme.info),
                  ),
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
              size: 20,
              color: AppTheme.textSecondary,
            ),
            tooltip: 'Refresh',
          ),
        if (!isConnected && sshState.credentials != null && !isReconnecting)
          IconButton(
            onPressed: () {
              ref.read(sftpProvider.notifier).retry();
            },
            icon: const Icon(Icons.wifi_off, size: 20, color: AppTheme.accent),
            tooltip: 'Reconnect',
          ),
      ],
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
                // Home button
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

                // Path breadcrumb - macOS Finder style
                Expanded(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: _buildPathBreadcrumbItems(sftpState),
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

  List<Widget> _buildPathBreadcrumbItems(SftpState sftpState) {
    final segments = sftpState.pathSegments;
    final widgets = <Widget>[];

    if (segments.isEmpty) return widgets;

    // If we have more than 2 segments, show "..." dropdown with hidden segments
    if (segments.length > 2) {
      final hiddenSegments = segments.sublist(0, segments.length - 2);

      widgets.add(
        InkWell(
          onTap: () => _showPathDropdown(context, hiddenSegments, sftpState),
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.more_horiz, size: 16, color: AppTheme.textSecondary),
                const Icon(
                  Icons.keyboard_arrow_down,
                  size: 12,
                  color: AppTheme.textSecondary,
                ),
              ],
            ),
          ),
        ),
      );

      widgets.add(
        const Icon(Icons.chevron_right, size: 14, color: AppTheme.textTertiary),
      );

      // Show the second-to-last segment (previous)
      final prevIndex = segments.length - 2;
      widgets.add(
        InkWell(
          onTap: () =>
              ref.read(sftpProvider.notifier).navigateToSegment(prevIndex),
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Text(
              segments[prevIndex],
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.normal,
              ),
            ),
          ),
        ),
      );

      widgets.add(
        const Icon(Icons.chevron_right, size: 14, color: AppTheme.textTertiary),
      );

      // Show the last segment (current) - highlighted
      widgets.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            segments.last,
            style: const TextStyle(
              color: AppTheme.accent,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
    } else {
      // 2 or fewer segments - show all
      for (int i = 0; i < segments.length; i++) {
        final isLast = i == segments.length - 1;

        if (i > 0) {
          widgets.add(
            const Icon(
              Icons.chevron_right,
              size: 14,
              color: AppTheme.textTertiary,
            ),
          );
        }

        if (isLast) {
          // Current directory - highlighted
          widgets.add(
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                segments[i],
                style: const TextStyle(
                  color: AppTheme.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          );
        } else {
          // Previous directories - clickable
          widgets.add(
            InkWell(
              onTap: () => ref.read(sftpProvider.notifier).navigateToSegment(i),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Text(
                  segments[i],
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        }
      }
    }

    return widgets;
  }

  void _showPathDropdown(
    BuildContext context,
    List<String> hiddenSegments,
    SftpState sftpState,
  ) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(const Offset(0, 30), ancestor: overlay),
        button.localToGlobal(
          button.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );

    showMenu(
      context: context,
      position: position,
      color: AppTheme.surface,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppTheme.border),
      ),
      items: hiddenSegments.asMap().entries.map((entry) {
        final index = entry.key;
        final segment = entry.value;

        // Build full path up to this segment
        final fullPath = sftpState.pathSegments.sublist(0, index + 1).join('/');

        return PopupMenuItem<String>(
          value: fullPath,
          height: 36,
          child: Row(
            children: [
              Icon(
                Icons.folder,
                size: 16,
                color: AppTheme.accent.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  segment,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          onTap: () {
            HapticFeedback.lightImpact();
            ref.read(sftpProvider.notifier).navigateToSegment(index);
          },
        );
      }).toList(),
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
    if (sftpState.isSelectionMode) {
      return _buildSelectionModeToolbar(sftpState);
    }
    return const SizedBox.shrink();
  }

  Widget _buildSelectionModeToolbar(SftpState sftpState) {
    final selectedCount = sftpState.selectedPaths.length;
    final hasSelection = selectedCount > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              ref.read(sftpProvider.notifier).toggleSelectionMode();
            },
            icon: const Icon(Icons.close, color: AppTheme.textPrimary),
            tooltip: 'Cancel selection',
          ),
          const SizedBox(width: 16),
          Text(
            '$selectedCount selected',
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: hasSelection
                ? () {
                    HapticFeedback.selectionClick();
                    _downloadSelected(context);
                  }
                : null,
            icon: Icon(
              Icons.download,
              size: 20,
              color: hasSelection ? AppTheme.accent : AppTheme.textTertiary,
            ),
            tooltip: 'Download selected',
          ),
          IconButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              ref.read(sftpProvider.notifier).selectAllItems();
            },
            icon: const Icon(
              Icons.select_all,
              size: 20,
              color: AppTheme.textPrimary,
            ),
            tooltip: 'Select all',
          ),
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
        ],
      ),
    );
  }

  Future<void> _confirmDeleteSelected(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text(
          'Delete Items',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: const Text(
          'Are you sure you want to delete the selected items? This action cannot be undone.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppTheme.error),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(sftpProvider.notifier).deleteSelected();
    }
  }

  Future<void> _downloadSelected(BuildContext context) async {
    final sftpState = ref.read(sftpProvider);
    final selectedPaths = sftpState.selectedPaths;

    // Filter items to get actual SftpItem objects
    // We also need to filter out directories as we don't support recursive download yet
    final filesToDownload = sftpState.items
        .where((item) => selectedPaths.contains(item.path) && !item.isDirectory)
        .toList();

    final directoriesSkipped = sftpState.items
        .where((item) => selectedPaths.contains(item.path) && item.isDirectory)
        .length;

    if (filesToDownload.isEmpty) {
      if (directoriesSkipped > 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Directory download is not supported yet'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
      return;
    }

    int successCount = 0;

    // Download files sequentially
    for (final item in filesToDownload) {
      if (!mounted) break;
      final success = await _downloadFile(item, showSnackBars: false);
      if (success) successCount++;
    }

    if (mounted) {
      ref
          .read(sftpProvider.notifier)
          .toggleSelectionMode(); // Exit selection mode

      String message = 'Downloaded $successCount files';
      if (directoriesSkipped > 0) {
        message += ' ($directoriesSkipped directories skipped)';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
      );
    }
  }

  Future<bool> _downloadFile(SftpItem item, {bool showSnackBars = true}) async {
    // Check storage permission
    final hasPermission =
        await StoragePermissionService.requestStoragePermission();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Storage permission denied'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
      return false;
    }

    Directory? downloadsDir;
    if (Platform.isAndroid) {
      downloadsDir = Directory('/storage/emulated/0/Download');
    } else {
      downloadsDir = await getDownloadsDirectory();
    }

    if (downloadsDir == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not access downloads directory'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
      return false;
    }

    String localPath = p.join(downloadsDir.path, item.name);

    // Check if file exists
    if (File(localPath).existsSync()) {
      if (!mounted) return false;

      final result = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: const Text(
            'File Exists',
            style: TextStyle(color: AppTheme.textPrimary),
          ),
          content: Text(
            '${item.name} already exists. What would you like to do?',
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'cancel'),
              child: const Text(
                'Cancel',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'keep_both'),
              child: const Text('Keep Both'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'replace'),
              child: const Text('Replace'),
            ),
          ],
        ),
      );

      if (result == 'cancel' || result == null) return false;

      if (result == 'keep_both') {
        final extension = p.extension(item.name);
        final nameWithoutExtension = p.basenameWithoutExtension(item.name);
        int counter = 1;
        do {
          localPath = p.join(
            downloadsDir.path,
            '$nameWithoutExtension ($counter)$extension',
          );
          counter++;
        } while (File(localPath).existsSync());
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Downloaded to $localPath'),
          backgroundColor: AppTheme.success,
        ),
      );
    }
    return true;
  }
}

class _SftpListItem extends StatelessWidget {
  final SftpItem item;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _SftpListItem({
    required this.item,
    required this.isSelected,
    required this.isSelectionMode,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected
          ? AppTheme.accent.withValues(alpha: 0.1)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              if (isSelectionMode)
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Icon(
                    isSelected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 20,
                    color: isSelected ? AppTheme.accent : AppTheme.textTertiary,
                  ),
                ),
              Icon(
                _getIcon(item),
                size: 24,
                color: item.isDirectory
                    ? AppTheme.accent
                    : AppTheme.textSecondary,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: TextStyle(
                        color: isSelected
                            ? AppTheme.accent
                            : AppTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (!item.isDirectory) ...[
                          Text(
                            _formatSize(item.size ?? 0),
                            style: const TextStyle(
                              color: AppTheme.textTertiary,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            '•',
                            style: TextStyle(
                              color: AppTheme.textTertiary,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          _formatDate(item.modified ?? DateTime.now()),
                          style: const TextStyle(
                            color: AppTheme.textTertiary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getIcon(SftpItem item) {
    if (item.isDirectory) return Icons.folder;
    final extension = item.name.split('.').lastOrNull ?? '';
    return getIconForExtension(extension);
  }

  String _formatSize(int bytes) {
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double size = bytes.toDouble();
    while (size > 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(1)} ${suffixes[i]}';
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
