import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';

import '../models/file_node.dart';
import '../models/project.dart';
import '../models/session.dart';
import '../providers/providers.dart';
import '../services/file_service.dart';
import '../services/project_service.dart';
import '../theme/app_theme.dart';

final openProjectPathProvider = StateProvider<String?>((ref) => null);
final openProjectSearchProvider = StateProvider<String>((ref) => '');
final openProjectSearchResetProvider = StateProvider<int>((ref) => 0);

final openProjectDirectoryListProvider = FutureProvider.autoDispose
    .family<List<FileNode>, String>((ref, directory) async {
      if (directory.trim().isEmpty) return const [];
      final fileService = ref.watch(fileServiceProvider);
      return fileService.listDirectory(path: '', directory: directory);
    });

final openProjectSearchResultsProvider = FutureProvider.autoDispose
    .family<List<String>, ({String directory, String query})>((
      ref,
      args,
    ) async {
      final query = args.query.trim();
      if (query.isEmpty || args.directory.trim().isEmpty) return const [];
      final fileService = ref.watch(fileServiceProvider);
      if (query.contains('/')) {
        return _searchDirectoryPath(
          fileService: fileService,
          rootDirectory: args.directory,
          query: query,
        );
      }
      return fileService.searchDirectories(
        query: query,
        directory: args.directory,
        limit: 200,
      );
    });

class OpenProjectScreen extends ConsumerWidget {
  const OpenProjectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pathAsync = ref.watch(pathInfoProvider);
    final pathInfo = pathAsync.hasValue ? pathAsync.value : null;
    final initialPath = pathInfo?.home ?? '';
    final pathState = ref.watch(openProjectPathProvider);
    final currentPath = pathState ?? initialPath;
    final searchText = ref.watch(openProjectSearchProvider).trim();
    final searchReset = ref.watch(openProjectSearchResetProvider);

    final directoryListAsync = currentPath.isEmpty
        ? const AsyncValue<List<FileNode>>.loading()
        : ref.watch(openProjectDirectoryListProvider(currentPath));

    final searchResultsAsync = searchText.isEmpty || currentPath.isEmpty
        ? const AsyncValue<List<String>>.data([])
        : ref.watch(
            openProjectSearchResultsProvider((
              directory: currentPath,
              query: searchText,
            )),
          );

    if (pathAsync.hasError && pathInfo == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, size: 20),
            onPressed: () => context.pop(),
          ),
          title: const Text('Open Project'),
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 40, color: AppTheme.error),
              const SizedBox(height: 12),
              Text(
                pathAsync.error.toString(),
                style: const TextStyle(
                  color: AppTheme.textTertiary,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => ref.invalidate(pathInfoProvider),
                child: const Text('RETRY'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 20),
          onPressed: () => context.pop(),
        ),
        title: const Text('Open Project'),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              border: Border(bottom: BorderSide(color: AppTheme.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPathRow(
                  currentPath: currentPath,
                  canGoUp: _canGoUp(currentPath),
                  onGoUp: () => _goUp(ref, currentPath, initialPath),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  key: ValueKey(searchReset),
                  initialValue: searchText,
                  onChanged: (value) {
                    ref.read(openProjectSearchProvider.notifier).state = value;
                  },
                  decoration: const InputDecoration(
                    hintText: 'Search directories',
                    prefixIcon: Icon(Icons.search, size: 18),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: searchText.isNotEmpty
                ? _buildSearchResults(
                    ref: ref,
                    currentPath: currentPath,
                    searchText: searchText,
                    resultsAsync: searchResultsAsync,
                  )
                : _buildDirectoryList(
                    ref: ref,
                    currentPath: currentPath,
                    filesAsync: directoryListAsync,
                  ),
          ),
        ],
      ),
    );
  }
}

Widget _buildPathRow({
  required String currentPath,
  required bool canGoUp,
  required VoidCallback onGoUp,
}) {
  return Row(
    children: [
      IconButton(
        icon: const Icon(Icons.arrow_upward, size: 18),
        onPressed: canGoUp ? onGoUp : null,
        tooltip: 'Up',
      ),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          currentPath.isEmpty ? 'Loading path...' : currentPath,
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );
}

Widget _buildDirectoryList({
  required WidgetRef ref,
  required String currentPath,
  required AsyncValue<List<FileNode>> filesAsync,
}) {
  if (currentPath.isEmpty) {
    return const Center(
      child: CircularProgressIndicator(color: AppTheme.accent),
    );
  }

  return filesAsync.when(
    data: (nodes) {
      final directories =
          nodes.where((node) => node.isDirectory && !node.ignored).toList()
            ..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            );

      if (directories.isEmpty) {
        return _buildEmptyState();
      }

      return ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: directories.length,
        separatorBuilder: (context, index) => const SizedBox(height: 6),
        itemBuilder: (context, index) {
          final node = directories[index];
          return _DirectoryTile(
            title: Text(
              node.name,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              _compactPath(node.absolute),
              style: const TextStyle(
                color: AppTheme.textTertiary,
                fontSize: 11,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => _openProjectFromDirectory(context, ref, node.absolute),
          );
        },
      );
    },
    loading: () =>
        const Center(child: CircularProgressIndicator(color: AppTheme.accent)),
    error: (error, _) => Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 40, color: AppTheme.error),
          const SizedBox(height: 12),
          Text(
            error.toString(),
            style: const TextStyle(color: AppTheme.textTertiary, fontSize: 12),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () {
              ref.invalidate(openProjectDirectoryListProvider(currentPath));
            },
            child: const Text('RETRY'),
          ),
        ],
      ),
    ),
  );
}

Widget _buildSearchResults({
  required WidgetRef ref,
  required String currentPath,
  required String searchText,
  required AsyncValue<List<String>> resultsAsync,
}) {
  return resultsAsync.when(
    data: (nodes) {
      final directories = nodes.toSet().toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      if (directories.isEmpty) {
        return _buildEmptyState();
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              'Search Results',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              itemCount: directories.length,
              separatorBuilder: (context, index) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final node = directories[index];
                final destination = _resolveSearchPath(currentPath, node);
                final displayPath = _displaySearchPath(
                  currentPath,
                  destination,
                );
                final searchTail = _searchTail(searchText);
                return _DirectoryTile(
                  title: _buildHighlightedPathLabel(displayPath, searchTail),
                  onTap: () =>
                      _openProjectFromDirectory(context, ref, destination),
                );
              },
            ),
          ),
        ],
      );
    },
    loading: () =>
        const Center(child: CircularProgressIndicator(color: AppTheme.accent)),
    error: (error, _) => Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 40, color: AppTheme.error),
          const SizedBox(height: 12),
          Text(
            error.toString(),
            style: const TextStyle(color: AppTheme.textTertiary, fontSize: 12),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () {
              ref.invalidate(
                openProjectSearchResultsProvider((
                  directory: currentPath,
                  query: searchText,
                )),
              );
            },
            child: const Text('RETRY'),
          ),
        ],
      ),
    ),
  );
}

Widget _buildHighlightedPathLabel(String path, String queryTail) {
  final normalized = _trimTrailingSlash(path);
  final slash = normalized.lastIndexOf('/');
  final prefix = slash == -1 ? '' : normalized.substring(0, slash + 1);
  final leaf = slash == -1 ? normalized : normalized.substring(slash + 1);
  final leafLower = leaf.toLowerCase();
  final queryLower = queryTail.toLowerCase();
  final matchIndex = queryLower.isEmpty ? -1 : leafLower.indexOf(queryLower);

  if (matchIndex < 0) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: prefix,
            style: const TextStyle(color: AppTheme.textTertiary, fontSize: 13),
          ),
          TextSpan(
            text: leaf,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const TextSpan(
            text: '/',
            style: TextStyle(color: AppTheme.textTertiary, fontSize: 13),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  return Text.rich(
    TextSpan(
      children: [
        TextSpan(
          text: prefix,
          style: const TextStyle(color: AppTheme.textTertiary, fontSize: 13),
        ),
        TextSpan(
          text: leaf.substring(0, matchIndex),
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        TextSpan(
          text: leaf.substring(matchIndex, matchIndex + queryTail.length),
          style: const TextStyle(
            color: AppTheme.accent,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        TextSpan(
          text: leaf.substring(matchIndex + queryTail.length),
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const TextSpan(
          text: '/',
          style: TextStyle(color: AppTheme.textTertiary, fontSize: 13),
        ),
      ],
    ),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );
}

class _DirectoryTile extends StatelessWidget {
  const _DirectoryTile({
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  final Widget title;
  final Widget? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          border: Border.all(color: AppTheme.border),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.folder_outlined, color: AppTheme.accent, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  title,
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    subtitle!,
                  ],
                ],
              ),
            ),
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
}

Widget _buildEmptyState() {
  return Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.folder_off_outlined, size: 40, color: AppTheme.textTertiary),
        const SizedBox(height: 12),
        const Text(
          'No folders found',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        ),
      ],
    ),
  );
}

void _goUp(WidgetRef ref, String currentPath, String fallback) {
  final base = currentPath.isEmpty ? fallback : currentPath;
  if (!_canGoUp(base)) return;
  ref.read(openProjectPathProvider.notifier).state = _parentPath(base);
  _clearSearch(ref);
}

void _clearSearch(WidgetRef ref) {
  ref.read(openProjectSearchProvider.notifier).state = '';
  ref.read(openProjectSearchResetProvider.notifier).state++;
}

bool _canGoUp(String currentPath) {
  if (currentPath.isEmpty) return false;
  final parts = currentPath.split('/')..removeWhere((part) => part.isEmpty);
  return parts.isNotEmpty;
}

String _parentPath(String currentPath) {
  final parts = currentPath.split('/')..removeWhere((part) => part.isEmpty);
  if (parts.isEmpty) return '/';
  parts.removeLast();
  if (parts.isEmpty) return '/';
  return '/${parts.join('/')}';
}

String _joinPath(String base, String next) {
  if (base.isEmpty) return next;
  final trimmed = base.endsWith('/')
      ? base.substring(0, base.length - 1)
      : base;
  final cleaned = next.startsWith('/') ? next.substring(1) : next;
  final joined = '$trimmed/$cleaned';
  return _trimTrailingSlash(joined);
}

String _trimTrailingSlash(String path) {
  if (path.length <= 1) return path;
  return path.endsWith('/') ? path.substring(0, path.length - 1) : path;
}

String _resolveSearchPath(String currentPath, String searchResult) {
  final normalized = _trimTrailingSlash(searchResult.trim());
  if (normalized.startsWith('/')) {
    return normalized;
  }
  return _joinPath(currentPath, normalized);
}

String _searchTail(String searchText) {
  final normalized = searchText.trim().replaceAll('\\', '/');
  final parts = normalized.split('/');
  return parts.isEmpty ? normalized : parts.last.trim();
}

String _displaySearchPath(String currentPath, String destination) {
  final base = _trimTrailingSlash(currentPath);
  final path = _trimTrailingSlash(destination);
  if (path.startsWith('$base/')) {
    return path.substring(base.length + 1);
  }
  if (path.startsWith('/')) {
    return path.substring(1);
  }
  return path;
}

String _compactPath(String absolutePath) {
  if (absolutePath.startsWith('/home/')) {
    final segments = absolutePath.split('/');
    if (segments.length >= 4) {
      return '~/${segments.sublist(3).join('/')}';
    }
  }
  return absolutePath;
}

Future<List<String>> _searchDirectoryPath({
  required FileService fileService,
  required String rootDirectory,
  required String query,
}) async {
  final normalized = query.trim().replaceAll('\\', '/');
  final parts = normalized
      .split('/')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return const [];

  var current = _trimTrailingSlash(rootDirectory);
  for (var i = 0; i < parts.length - 1; i++) {
    final segment = parts[i];
    final entries = await fileService.listDirectory(
      path: '',
      directory: current,
    );
    final directories = entries
        .where((node) => node.isDirectory && !node.ignored)
        .toList();
    FileNode? next;
    for (final node in directories) {
      if (node.name.toLowerCase() == segment.toLowerCase()) {
        next = node;
        break;
      }
    }
    next ??= directories.cast<FileNode?>().firstWhere(
      (node) =>
          node != null &&
          node.name.toLowerCase().startsWith(segment.toLowerCase()),
      orElse: () => null,
    );
    if (next == null) return const [];
    current = _trimTrailingSlash(next.absolute);
  }

  final tail = parts.last.toLowerCase();
  final candidates = await fileService.listDirectory(
    path: '',
    directory: current,
  );
  return candidates
      .where((node) => node.isDirectory && !node.ignored)
      .where((node) => node.name.toLowerCase().contains(tail))
      .map((node) => node.absolute)
      .toList();
}

Future<void> _openProjectFromDirectory(
  BuildContext context,
  WidgetRef ref,
  String directory,
) async {
  try {
    final sessionService = ref.read(sessionServiceProvider);
    final session = await sessionService.createSession(directory: directory);
    final projectService = ref.read(projectServiceProvider);
    final project = await _resolveProject(session, directory, projectService);
    if (project != null) {
      ref.read(selectedProjectProvider.notifier).state = project;
      ref.read(projectModelProvider.notifier).load(project.id);
    }
    ref.read(selectedSessionProvider.notifier).state = session;
    ref.invalidate(sessionsProvider);
    if (context.mounted) {
      context.go('/chat/${session.id}');
    }
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Failed to open project: $e')));
  }
}

Future<Project?> _resolveProject(
  Session session,
  String directory,
  ProjectService projectService,
) async {
  final projects = await projectService.listProjects(directory: directory);
  Project? match;
  for (final project in projects) {
    if (project.id == session.projectID || project.worktree == directory) {
      match = project;
      break;
    }
  }
  match ??= projects.isNotEmpty ? projects.first : null;
  if (match != null) return match;
  try {
    return await projectService.getCurrentProject(directory: directory);
  } catch (_) {
    return null;
  }
}
