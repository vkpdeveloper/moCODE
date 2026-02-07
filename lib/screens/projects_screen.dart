import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/providers.dart';
import '../theme/app_theme.dart';

class ProjectsScreen extends ConsumerWidget {
  const ProjectsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectsAsync = ref.watch(projectsProvider);
    final healthAsync = ref.watch(healthProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.accent),
              ),
              child: Text(
                'meCODE',
                style: TextStyle(
                  color: AppTheme.accent,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
            ),
            const SizedBox(width: 12),
            healthAsync.when(
              data: (health) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: health.healthy ? AppTheme.success.withValues(alpha: 0.15) : AppTheme.error.withValues(alpha: 0.15),
                  border: Border.all(
                    color: health.healthy ? AppTheme.success : AppTheme.error,
                  ),
                ),
                child: Text(
                  health.healthy ? 'ONLINE' : 'OFFLINE',
                  style: TextStyle(
                    color: health.healthy ? AppTheme.success : AppTheme.error,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              loading: () => const SizedBox.shrink(),
              error: (_,  _) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.error.withValues(alpha: 0.15),
                  border: Border.all(color: AppTheme.error),
                ),
                child: const Text(
                  'OFFLINE',
                  style: TextStyle(color: AppTheme.error, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: projectsAsync.when(
        data: (projects) {
          if (projects.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.folder_off_outlined, size: 48, color: AppTheme.textTertiary),
                  const SizedBox(height: 16),
                  Text(
                    'No projects found',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Start meCode in a project directory',
                    style: TextStyle(color: AppTheme.textTertiary, fontSize: 12),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            color: AppTheme.accent,
            backgroundColor: AppTheme.surface,
            onRefresh: () async {
              ref.invalidate(projectsProvider);
              ref.invalidate(healthProvider);
            },
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: projects.length,
              separatorBuilder: (_,  _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final project = projects[index];
                final projectName = project.name ?? project.worktree.split('/').last;
                
                return GestureDetector(
                  onTap: () {
                    ref.read(selectedProjectProvider.notifier).state = project;
                    context.push('/sessions');
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      border: Border.all(color: AppTheme.border),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.folder_outlined, color: AppTheme.accent, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                projectName,
                                style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const Icon(Icons.chevron_right, color: AppTheme.textTertiary, size: 20),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          project.worktree,
                          style: const TextStyle(
                            color: AppTheme.textTertiary,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            if (project.vcs != null) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.info.withValues(alpha: 0.1),
                                  border: Border.all(color: AppTheme.info.withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.commit, color: AppTheme.info, size: 12),
                                    const SizedBox(width: 4),
                                    Text(
                                      'VCS',
                                      style: TextStyle(color: AppTheme.info, fontSize: 10),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceVariant,
                                border: Border.all(color: AppTheme.border),
                              ),
                              child: Text(
                                _timeAgo(project.time.updated ?? project.time.created),
                                style: const TextStyle(color: AppTheme.textTertiary, fontSize: 10),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppTheme.accent),
        ),
        error: (error, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: AppTheme.error),
              const SizedBox(height: 16),
              Text(
                'Failed to load projects',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 8),
              Text(
                error.toString(),
                style: TextStyle(color: AppTheme.textTertiary, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => ref.invalidate(projectsProvider),
                child: const Text('RETRY'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _timeAgo(int timestampMs) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final diff = (now - timestampMs) ~/ 1000;
    if (diff < 60) return 'just now';
    if (diff < 3600) return '${diff ~/ 60}m ago';
    if (diff < 86400) return '${diff ~/ 3600}h ago';
    return '${diff ~/ 86400}d ago';
  }
}
