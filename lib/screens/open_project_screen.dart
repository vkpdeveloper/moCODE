import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/project.dart';
import '../models/session.dart';
import '../services/project_service.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';

class OpenProjectScreen extends ConsumerStatefulWidget {
  const OpenProjectScreen({super.key});

  @override
  ConsumerState<OpenProjectScreen> createState() => _OpenProjectScreenState();
}

class _OpenProjectScreenState extends ConsumerState<OpenProjectScreen> {
  final TextEditingController _searchController = TextEditingController();
  String? _currentPath;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pathAsync = ref.watch(pathInfoProvider);
    final pathInfo = pathAsync.valueOrNull;
    final initialPath = pathInfo?.home ?? '';
    final currentPath = _currentPath ?? initialPath;
    final searchText = _searchController.text.trim();

    final filesAsync = currentPath.isEmpty
        ? const AsyncValue<List<String>>.loading()
        : ref.watch(
            fileListProvider((path: searchText, directory: currentPath)),
          );

    final greeting = _buildGreeting(pathInfo?.home);

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
                if (greeting.isNotEmpty)
                  Text(
                    greeting,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                if (greeting.isNotEmpty) const SizedBox(height: 8),
                _buildPathRow(currentPath),
                const SizedBox(height: 10),
                TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Type to jump into a subfolder',
                    prefixIcon: Icon(Icons.search, size: 18),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: filesAsync.when(
              data: (nodes) {
                final directories = nodes.toList()
                  ..sort((a, b) => a.compareTo(b));

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
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final node = directories[index];
                    return GestureDetector(
                      onTap: () => _enterDirectory(node),
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
                  : () => _selectFolder(currentPath),
              icon: const Icon(Icons.check, size: 16),
              label: const Text('SELECT'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPathRow(String currentPath) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_upward, size: 18),
          onPressed: _canGoUp(currentPath) ? _goUp : null,
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

  void _enterDirectory(String node) {
    if (node.startsWith('/')) {
      setState(() {
        _currentPath = node;
        _searchController.clear();
      });
      return;
    }
    final pathInfo = ref.read(pathInfoProvider).valueOrNull;
    final base = _currentPath ?? pathInfo?.home ?? '';
    final nextPath = _joinPath(base, node);
    setState(() {
      _currentPath = nextPath;
      _searchController.clear();
    });
  }

  void _goUp() {
    final pathInfo = ref.read(pathInfoProvider).valueOrNull;
    final currentPath = _currentPath ?? pathInfo?.home ?? '';
    if (!_canGoUp(currentPath)) return;
    final parts = currentPath.split('/')..removeWhere((part) => part.isEmpty);
    if (parts.isEmpty) return;
    parts.removeLast();
    final parent = '/${parts.join('/')}';
    setState(() {
      _currentPath = parent.isEmpty ? '/' : parent;
      _searchController.clear();
    });
  }

  bool _canGoUp(String currentPath) {
    if (currentPath.isEmpty) return false;
    final parts = currentPath.split('/')..removeWhere((part) => part.isEmpty);
    return parts.isNotEmpty;
  }

  String _joinPath(String base, String next) {
    if (base.isEmpty) return next;
    final trimmed = base.endsWith('/')
        ? base.substring(0, base.length - 1)
        : base;
    final cleaned = next.startsWith('/') ? next.substring(1) : next;
    final joined = '$trimmed/$cleaned';
    return joined.endsWith('/') && joined.length > 1
        ? joined.substring(0, joined.length - 1)
        : joined;
  }

  String _buildGreeting(String? homePath) {
    if (homePath == null || homePath.isEmpty) return '';
    final parts = homePath.split('/')..removeWhere((part) => part.isEmpty);
    if (parts.length < 2) return 'Welcome back';
    final username = parts[1];
    if (username.isEmpty) return 'Welcome back';
    return 'Welcome back, $username';
  }

  Future<void> _selectFolder(String directory) async {
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
      if (mounted) {
        context.go('/chat/${session.id}');
      }
    } catch (e) {
      if (!mounted) return;
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
}
