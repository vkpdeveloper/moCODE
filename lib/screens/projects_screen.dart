import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../extensions/async_value_extensions.dart';
import '../models/project.dart';
import '../models/session.dart';
import '../providers/providers.dart';
import '../providers/ssh_provider.dart';
import '../models/server_type.dart';
import '../services/error_handler.dart';
import '../theme/app_theme.dart';
import '../widgets/connection_choice_sheet.dart';
import '../widgets/connection_error_view.dart';
import '../widgets/ssh_connection_dialog.dart';
import 'sftp_page.dart';
import 'terminal_page.dart';

final mergedProjectsProvider = FutureProvider<List<Project>>((ref) async {
  final projectService = ref.watch(projectServiceProvider);
  final sessionService = ref.watch(sessionServiceProvider);
  final results = await Future.wait([
    projectService.listProjects(),
    sessionService.listSessions(limit: 200, roots: false),
  ]);
  final projects = results[0] as List<Project>;
  final sessions = results[1] as List<Session>;

  final mergedByDirectory = <String, Project>{};
  for (final project in projects) {
    final normalizedDirectory = _normalizeDirectory(project.worktree);
    if (normalizedDirectory.isEmpty) continue;
    mergedByDirectory[normalizedDirectory] = project;
  }

  final latestSessionByDirectory = <String, Session>{};
  for (final session in sessions) {
    final normalizedDirectory = _normalizeDirectory(session.directory);
    if (normalizedDirectory.isEmpty) continue;
    final existing = latestSessionByDirectory[normalizedDirectory];
    if (existing == null || session.time.updated > existing.time.updated) {
      latestSessionByDirectory[normalizedDirectory] = session;
    }
  }

  for (final entry in latestSessionByDirectory.entries) {
    final normalizedDirectory = entry.key;
    final session = entry.value;
    final existingProject = mergedByDirectory[normalizedDirectory];

    if (existingProject != null) {
      final projectUpdated = existingProject.time.updated ?? 0;
      final latestUpdated = session.time.updated > projectUpdated
          ? session.time.updated
          : projectUpdated;
      mergedByDirectory[normalizedDirectory] = Project(
        id: existingProject.id,
        worktree: existingProject.worktree,
        vcs: existingProject.vcs,
        name: existingProject.name ?? _directoryName(existingProject.worktree),
        icon: existingProject.icon,
        commands: existingProject.commands,
        sandboxes: existingProject.sandboxes,
        time: ProjectTime(
          created: existingProject.time.created,
          updated: latestUpdated,
          initialized: existingProject.time.initialized,
        ),
      );
      continue;
    }

    mergedByDirectory[normalizedDirectory] = Project(
      id: session.projectID,
      worktree: normalizedDirectory,
      name: _directoryName(normalizedDirectory),
      time: ProjectTime(
        created: session.time.created,
        updated: session.time.updated,
      ),
    );
  }

  final merged = mergedByDirectory.values.toList()
    ..sort((a, b) => (b.time.updated ?? 0).compareTo(a.time.updated ?? 0));
  return merged;
});

String _normalizeDirectory(String directory) {
  final trimmed = directory.trim();
  if (trimmed.isEmpty) return '';
  if (trimmed.length > 1 && trimmed.endsWith('/')) {
    return trimmed.substring(0, trimmed.length - 1);
  }
  return trimmed;
}

String _directoryName(String directory) {
  final normalized = _normalizeDirectory(directory);
  final parts = normalized.split('/').where((part) => part.isNotEmpty).toList();
  if (parts.isEmpty) return normalized;
  return parts.last;
}

class ProjectsScreen extends ConsumerWidget {
  const ProjectsScreen({super.key});

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    if (hour < 21) return 'Good evening';
    return 'Late night coding';
  }

  String _getDevMessage() {
    final hour = DateTime.now().hour;
    if (hour < 6) return '☕ Burning the midnight oil? Let\'s ship some code.';
    if (hour < 12) return '🚀 Ready to build something awesome?';
    if (hour < 17) return '⚡ Time to crush some bugs and ship features.';
    if (hour < 21) return '💻 Evening productivity session activated.';
    return '🌙 The best code is written when the world sleeps.';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectsAsync = ref.watch(mergedProjectsProvider);
    final healthAsync = ref.watch(healthProvider);
    final settings = ref.watch(settingsProvider);
    final isCodex = settings.activeServerType == ServerType.codex;

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
                'moCODE',
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
                  color: health.healthy
                      ? AppTheme.success.withValues(alpha: 0.15)
                      : AppTheme.error.withValues(alpha: 0.15),
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
              error: (_, _) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.error.withValues(alpha: 0.15),
                  border: Border.all(color: AppTheme.error),
                ),
                child: const Text(
                  'OFFLINE',
                  style: TextStyle(
                    color: AppTheme.error,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.build_circle_outlined, size: 20),
            tooltip: 'Tools',
            onPressed: isCodex ? null : () => _showToolsMenu(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),

      body: Column(
        children: [
          // Developer Greeting Header
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
                Text(
                  _getGreeting(),
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _getDevMessage(),
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: projectsAsync.when(
              data: (projects) {
                if (projects.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.folder_off_outlined,
                          size: 48,
                          color: AppTheme.textTertiary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          isCodex ? 'No workspace configured' : 'No projects found',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isCodex
                              ? 'Set Codex workspace in Settings'
                              : 'Start moCODE in a project directory',
                          style: TextStyle(
                            color: AppTheme.textTertiary,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (!isCodex)
                          ElevatedButton.icon(
                            onPressed: () => context.push('/projects/open'),
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('OPEN PROJECT'),
                          ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  color: AppTheme.accent,
                  backgroundColor: AppTheme.surface,
                  onRefresh: () async {
                    ref.invalidate(mergedProjectsProvider);
                    ref.invalidate(healthProvider);
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: projects.length + (isCodex ? 0 : 1),
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      if (!isCodex && index == 0) {
                        return GestureDetector(
                          onTap: () => context.push('/projects/open'),
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceVariant,
                              border: Border.all(color: AppTheme.border),
                            ),
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.add_circle_outline,
                                  color: AppTheme.accent,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Text(
                                    'Open a new project',
                                    style: TextStyle(
                                      color: AppTheme.textPrimary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const Icon(
                                  Icons.chevron_right,
                                  color: AppTheme.textTertiary,
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      final project = projects[index - (isCodex ? 0 : 1)];
                      final projectName =
                          project.name ?? project.worktree.split('/').last;

                      return GestureDetector(
                        onTap: () {
                          ref.read(selectedProjectProvider.notifier).state =
                              project;
                          ref
                              .read(projectModelProvider.notifier)
                              .load(project.id);
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
                                  Icon(
                                    Icons.folder_outlined,
                                    color: AppTheme.accent,
                                    size: 20,
                                  ),
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
                                  const Icon(
                                    Icons.chevron_right,
                                    color: AppTheme.textTertiary,
                                    size: 20,
                                  ),
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
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppTheme.info.withValues(
                                          alpha: 0.1,
                                        ),
                                        border: Border.all(
                                          color: AppTheme.info.withValues(
                                            alpha: 0.3,
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.commit,
                                            color: AppTheme.info,
                                            size: 12,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'VCS',
                                            style: TextStyle(
                                              color: AppTheme.info,
                                              fontSize: 10,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.surfaceVariant,
                                      border: Border.all(
                                        color: AppTheme.border,
                                      ),
                                    ),
                                    child: Text(
                                      _timeAgo(project.time.updated!),
                                      style: const TextStyle(
                                        color: AppTheme.textTertiary,
                                        fontSize: 10,
                                      ),
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
              error: (error, _) {
                final apiError = ErrorHandler.parseError(error);
                return ConnectionErrorView(
                  error: apiError,
                  onRetry: () => ref.invalidate(mergedProjectsProvider),
                  showConfigureButton: apiError.shouldShowConfigure,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _timeAgo(int timestampMs) {
    final localTime = DateTime.fromMillisecondsSinceEpoch(
      timestampMs,
      isUtc: true,
    ).toLocal();
    final diff = DateTime.now().difference(localTime).inSeconds;
    if (diff < 60) return 'just now';
    if (diff < 3600) return '${diff ~/ 60}m ago';
    if (diff < 86400) return '${diff ~/ 3600}h ago';
    return '${diff ~/ 86400}d ago';
  }

  void _showToolsMenu(BuildContext context, WidgetRef ref) {
    final pathInfo = ref.read(pathInfoProvider).valueOrNull;
    final settings = ref.read(settingsProvider);
    final sshState = ref.read(sshProvider);
    final home = pathInfo?.home ?? '/';

    showConnectionChoiceSheet(
      context,
      onTerminal: () async {
        Navigator.pop(context);
        if (sshState.isConnected) {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (context) => const TerminalPage()));
        } else {
          final connected = await showSshConnectionDialog(
            context,
            defaultHost: settings.serverHost,
            workingDirectory: home,
          );
          if (connected == true && context.mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => const TerminalPage()),
            );
          }
        }
      },
      onSftp: () async {
        Navigator.pop(context);
        if (sshState.isConnected) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => SftpPage(workingDirectory: home),
            ),
          );
        } else {
          final connected = await showSshConnectionDialog(
            context,
            defaultHost: settings.serverHost,
            workingDirectory: home,
          );
          if (connected == true && context.mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => SftpPage(workingDirectory: home),
              ),
            );
          }
        }
      },
    );
  }
}
