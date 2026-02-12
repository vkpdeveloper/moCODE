import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/project.dart';
import '../models/session.dart';
import '../services/project_service.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';

final openProjectPathProvider = StateProvider<String?>((ref) => null);
final openProjectSearchProvider = StateProvider<String>((ref) => '');
final openProjectSearchResetProvider = StateProvider<int>((ref) => 0);

class FileTreeNodeState {
  final bool expanded;
  final bool loaded;
  final bool loading;
  final String? error;
  final List<String> children;

  const FileTreeNodeState({
    this.expanded = false,
    this.loaded = false,
    this.loading = false,
    this.error,
    this.children = const [],
  });

  FileTreeNodeState copyWith({
    bool? expanded,
    bool? loaded,
    bool? loading,
    String? error,
    List<String>? children,
  }) {
    return FileTreeNodeState(
      expanded: expanded ?? this.expanded,
      loaded: loaded ?? this.loaded,
      loading: loading ?? this.loading,
      error: error,
      children: children ?? this.children,
    );
  }
}

class FileTreeState {
  final Map<String, FileTreeNodeState> nodes;

  const FileTreeState({this.nodes = const {}});

  FileTreeState copyWith({Map<String, FileTreeNodeState>? nodes}) {
    return FileTreeState(nodes: nodes ?? this.nodes);
  }

  FileTreeNodeState node(String path) {
    return nodes[path] ?? const FileTreeNodeState();
  }
}

class FileTreeNotifier extends StateNotifier<FileTreeState> {
  FileTreeNotifier(this.ref, this.root) : super(const FileTreeState()) {
    if (root.isNotEmpty) {
      load(root);
    }
  }

  final Ref ref;
  final String root;
  final Map<String, Future<void>> _inflight = {};

  Future<void> load(String directory, {bool force = false}) async {
    if (directory.isEmpty) return;
    final current = state.node(directory);
    if (!force && current.loaded) return;
    final inflight = _inflight[directory];
    if (inflight != null) return inflight;

    _setNode(
      directory,
      current.copyWith(loading: true, error: null),
    );

    final promise = ref
        .read(fileListProvider((path: '/', directory: directory)).future)
        .then((entries) {
      final children = _normalizeEntries(directory, entries);
      _setNode(
        directory,
        current.copyWith(
          loaded: true,
          loading: false,
          error: null,
          children: children,
        ),
      );
    }).catchError((error) {
      _setNode(
        directory,
        current.copyWith(
          loading: false,
          error: error.toString(),
        ),
      );
    }).whenComplete(() {
      _inflight.remove(directory);
    });

    _inflight[directory] = promise;
    return promise;
  }

  void toggle(String directory) {
    final current = state.node(directory);
    final nextExpanded = !current.expanded;
    _setNode(directory, current.copyWith(expanded: nextExpanded));
    if (nextExpanded) {
      load(directory);
    }
  }

  void expand(String directory) {
    final current = state.node(directory);
    if (current.expanded) return;
    _setNode(directory, current.copyWith(expanded: true));
    load(directory);
  }

  void collapse(String directory) {
    final current = state.node(directory);
    if (!current.expanded) return;
    _setNode(directory, current.copyWith(expanded: false));
  }

  void _setNode(String directory, FileTreeNodeState node) {
    final next = Map<String, FileTreeNodeState>.from(state.nodes);
    next[directory] = node;
    state = state.copyWith(nodes: next);
  }
}

final fileTreeProvider = StateNotifierProvider.family<FileTreeNotifier, FileTreeState, String>(
  (ref, root) => FileTreeNotifier(ref, root),
);

class _TreeEntry {
  final String path;
  final int depth;

  const _TreeEntry({required this.path, required this.depth});
}

class OpenProjectScreen extends ConsumerWidget {
  const OpenProjectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pathAsync = ref.watch(pathInfoProvider);
    final pathInfo = pathAsync.valueOrNull;
    final initialPath = pathInfo?.home ?? '';
    final pathState = ref.watch(openProjectPathProvider);
    final currentPath = pathState ?? initialPath;
    final searchText = ref.watch(openProjectSearchProvider).trim();
    final searchReset = ref.watch(openProjectSearchResetProvider);

    final filesAsync = currentPath.isEmpty
        ? const AsyncValue<List<String>>.loading()
        : ref.watch(
            fileListProvider((path: searchText, directory: currentPath)),
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
                    hintText: 'Type to jump into a subfolder',
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
                    filesAsync: filesAsync,
                  )
                : _buildTree(
                    ref: ref,
                    currentPath: currentPath,
                  ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        decoration: BoxDecoration(
          color: AppTheme.background,
          border: Border(top: BorderSide(color: AppTheme.border)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                currentPath.isEmpty ? 'No folder selected' : currentPath,
                style: const TextStyle(
                  color: AppTheme.textTertiary,
                  fontSize: 10,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: currentPath.isEmpty
                  ? null
                  : () => _selectFolder(context, ref, currentPath),
              icon: const Icon(Icons.check, size: 16),
              label: const Text('SELECT'),
            ),
          ],
        ),
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

Widget _buildSearchResults({
  required WidgetRef ref,
  required String currentPath,
  required String searchText,
  required AsyncValue<List<String>> filesAsync,
}) {
  return filesAsync.when(
    data: (nodes) {
      final directories = nodes.toList()..sort((a, b) => a.compareTo(b));

      if (directories.isEmpty) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.folder_off_outlined,
                size: 40,
                color: AppTheme.textTertiary,
              ),
              const SizedBox(height: 12),
              const Text(
                'No folders found',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        );
      }

      return ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: directories.length,
        separatorBuilder: (context, index) => const SizedBox(height: 6),
        itemBuilder: (context, index) {
          final node = directories[index];
          return GestureDetector(
            onTap: () => _enterDirectory(ref, node, currentPath),
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.surface,
                border: Border.all(color: AppTheme.border),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.folder_outlined,
                    color: AppTheme.accent,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      node,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
        },
      );
    },
    loading: () => const Center(
      child: CircularProgressIndicator(color: AppTheme.accent),
    ),
    error: (error, _) => Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 40, color: AppTheme.error),
          const SizedBox(height: 12),
          Text(
            error.toString(),
            style: const TextStyle(
              color: AppTheme.textTertiary,
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () {
              ref.invalidate(
                fileListProvider((
                  path: searchText,
                  directory: currentPath,
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

Widget _buildTree({
  required WidgetRef ref,
  required String currentPath,
}) {
  if (currentPath.isEmpty) {
    return const Center(
      child: CircularProgressIndicator(color: AppTheme.accent),
    );
  }

  final treeState = ref.watch(fileTreeProvider(currentPath));
  final treeNotifier = ref.read(fileTreeProvider(currentPath).notifier);
  final rootState = treeState.node(currentPath);
  final visibleNodes = _buildVisibleNodes(currentPath, treeState);

  if (rootState.loaded && visibleNodes.isEmpty) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.folder_off_outlined,
            size: 40,
            color: AppTheme.textTertiary,
          ),
          const SizedBox(height: 12),
          const Text(
            'No folders found',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  return ListView.builder(
    padding: const EdgeInsets.all(12),
    itemCount: visibleNodes.length,
    itemBuilder: (context, index) {
      final entry = visibleNodes[index];
      final nodeState = treeState.node(entry.path);
      final depth = entry.depth;
      return Column(
        key: ValueKey(entry.path),
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              border: Border.all(color: AppTheme.border),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            margin: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                SizedBox(width: depth * 16),
                IconButton(
                  icon: Icon(
                    nodeState.expanded
                        ? Icons.expand_more
                        : Icons.chevron_right,
                    size: 18,
                    color: AppTheme.textTertiary,
                  ),
                  onPressed: () => treeNotifier.toggle(entry.path),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                ),
                Icon(
                  Icons.folder_outlined,
                  color: AppTheme.accent,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _leafName(entry.path),
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: () => _selectDirectory(ref, entry.path),
                  child: const Text('SELECT'),
                ),
              ],
            ),
          ),
          if (nodeState.expanded && nodeState.loading)
            Padding(
              padding: EdgeInsets.only(left: (depth + 1) * 16, bottom: 8),
              child: const Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.accent,
                  ),
                ),
              ),
            ),
          if (nodeState.expanded && nodeState.error != null)
            Padding(
              padding: EdgeInsets.only(left: (depth + 1) * 16, bottom: 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 16,
                    color: AppTheme.error,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      nodeState.error ?? 'Failed to load folder',
                      style: const TextStyle(
                        color: AppTheme.textTertiary,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        treeNotifier.load(entry.path, force: true),
                    child: const Text('RETRY'),
                  ),
                ],
              ),
            ),
        ],
      );
    },
  );
}

List<_TreeEntry> _buildVisibleNodes(String root, FileTreeState state) {
  final result = <_TreeEntry>[];

  void visit(String dir, int depth) {
    final node = state.node(dir);
    for (final child in node.children) {
      result.add(_TreeEntry(path: child, depth: depth));
      final childState = state.node(child);
      if (childState.expanded) {
        visit(child, depth + 1);
      }
    }
  }

  visit(root, 0);
  return result;
}

void _selectDirectory(WidgetRef ref, String directory) {
  ref.read(openProjectPathProvider.notifier).state = directory;
  _clearSearch(ref);
}

void _enterDirectory(WidgetRef ref, String node, String currentPath) {
  final nextPath = node.startsWith('/') ? node : _joinPath(currentPath, node);
  ref.read(openProjectPathProvider.notifier).state = nextPath;
  _clearSearch(ref);
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

String _leafName(String path) {
  final normalized = _trimTrailingSlash(path);
  final index = normalized.lastIndexOf('/');
  if (index == -1) return normalized;
  return normalized.substring(index + 1);
}

List<String> _normalizeEntries(String directory, List<String> entries) {
  final out = <String>{};
  for (final entry in entries) {
    var relative = entry.trim();
    if (relative.isEmpty) continue;

    if (relative.startsWith('/')) {
      final absolute = _trimTrailingSlash(relative);
      if (!absolute.startsWith(directory)) continue;
      relative = absolute.substring(directory.length);
      if (relative.startsWith('/')) {
        relative = relative.substring(1);
      }
    }

    relative = _trimTrailingSlash(relative);
    if (relative.isEmpty) continue;

    final firstSlash = relative.indexOf('/');
    final immediate = firstSlash == -1 ? relative : relative.substring(0, firstSlash);
    if (immediate.isEmpty) continue;

    final child = _joinPath(directory, immediate);
    if (child == directory) continue;
    out.add(child);
  }
  final list = out.toList();
  list.sort((a, b) => _leafName(a).compareTo(_leafName(b)));
  return list;
}

Future<void> _selectFolder(
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
