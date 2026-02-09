import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/session_busy_indicator.dart';

class SessionsScreen extends ConsumerWidget {
  const SessionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(selectedProjectProvider);
    final sessionsAsync = ref.watch(sessionsProvider);
    final vcsAsync = ref.watch(vcsInfoProvider);
    final statusAsync = ref.watch(sessionStatusProvider);
    final projectModelState = ref.watch(projectModelProvider);

    if (project == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.go('/projects');
      });
      return const SizedBox.shrink();
    }

    if (projectModelState.isLoading ||
        projectModelState.projectId != project.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(projectModelProvider.notifier).load(project.id);
      });
    }

    final projectName = project.name ?? project.worktree.split('/').last;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 20),
          onPressed: () => context.go('/projects'),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              projectName,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            vcsAsync.when(
              data: (vcs) => Row(
                children: [
                  Icon(Icons.commit, size: 10, color: AppTheme.info),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      vcs.branch ?? 'unknown',
                      style: TextStyle(fontSize: 10, color: AppTheme.info),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.swap_horiz, size: 20),
            tooltip: 'Models',
            onPressed: () =>
                context.push('/models', extra: {'mode': 'project'}),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 20),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: sessionsAsync.when(
        data: (sessions) {
          if (sessions.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.chat_bubble_outline,
                    size: 48,
                    color: AppTheme.textTertiary,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No sessions yet',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Create a new session to get started',
                    style: TextStyle(
                      color: AppTheme.textTertiary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => _createSession(context, ref),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('NEW SESSION'),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            color: AppTheme.accent,
            backgroundColor: AppTheme.surface,
            onRefresh: () async {
              ref.invalidate(sessionsProvider);
              ref.invalidate(vcsInfoProvider);
              ref.invalidate(sessionStatusProvider);
            },
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: sessions.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final session = sessions[index];
                final isArchived = session.time.archived != null;
                final sessionStatus = statusAsync.valueOrNull?[session.id];
                final isSessionBusy =
                    sessionStatus != null &&
                    sessionStatus != 'idle' &&
                    (sessionStatus is! Map || sessionStatus['type'] != 'idle');

                return GestureDetector(
                  onTap: () {
                    ref.read(selectedSessionProvider.notifier).state = session;
                    context.push('/chat/${session.id}');
                  },
                  onLongPress: () => _showSessionOptions(context, ref, session),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isArchived
                          ? AppTheme.background
                          : AppTheme.surface,
                      border: Border.all(
                        color: isSessionBusy
                            ? AppTheme.warning
                            : isArchived
                            ? AppTheme.border.withValues(alpha: 0.5)
                            : AppTheme.border,
                      ),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                session.title.isEmpty
                                    ? 'Untitled Session'
                                    : session.title,
                                style: TextStyle(
                                  color: isArchived
                                      ? AppTheme.textTertiary
                                      : AppTheme.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isSessionBusy) SessionItemBusyIndicator(),
                            if (session.parentID != null) ...[
                              if (isSessionBusy) const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: AppTheme.textTertiary,
                                  ),
                                ),
                                child: const Text(
                                  'FORK',
                                  style: TextStyle(
                                    color: AppTheme.textTertiary,
                                    fontSize: 8,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Text(
                              _formatTime(session.time.created),
                              style: const TextStyle(
                                color: AppTheme.textTertiary,
                                fontSize: 10,
                              ),
                            ),
                            if (session.summary != null) ...[
                              const SizedBox(width: 12),
                              Text(
                                '+${session.summary!.additions}',
                                style: const TextStyle(
                                  color: AppTheme.success,
                                  fontSize: 10,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '-${session.summary!.deletions}',
                                style: const TextStyle(
                                  color: AppTheme.error,
                                  fontSize: 10,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${session.summary!.files}f',
                                style: const TextStyle(
                                  color: AppTheme.textTertiary,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                            const Spacer(),
                            if (session.share != null)
                              Icon(Icons.share, size: 12, color: AppTheme.info),
                            if (isArchived) ...[
                              const SizedBox(width: 6),
                              Icon(
                                Icons.archive_outlined,
                                size: 12,
                                color: AppTheme.textTertiary,
                              ),
                            ],
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
                error.toString(),
                style: const TextStyle(
                  color: AppTheme.textTertiary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => ref.invalidate(sessionsProvider),
                child: const Text('RETRY'),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(color: AppTheme.accent),
        child: IconButton(
          icon: const Icon(Icons.add, color: Colors.white),
          onPressed: () => _createSession(context, ref),
        ),
      ),
    );
  }

  Future<void> _createSession(BuildContext context, WidgetRef ref) async {
    final project = ref.read(selectedProjectProvider);
    if (project == null) return;

    try {
      final sessionService = ref.read(sessionServiceProvider);
      final session = await sessionService.createSession(
        directory: project.worktree,
      );
      ref.invalidate(sessionsProvider);
      ref.read(selectedSessionProvider.notifier).state = session;
      if (context.mounted) {
        context.push('/chat/${session.id}');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to create session: $e')));
      }
    }
  }

  void _showSessionOptions(
    BuildContext context,
    WidgetRef ref,
    dynamic session,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Container(
        color: AppTheme.surface,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 3,
              color: AppTheme.border,
              margin: const EdgeInsets.only(bottom: 8),
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline,
                color: AppTheme.error,
                size: 20,
              ),
              title: const Text(
                'Delete Session',
                style: TextStyle(color: AppTheme.error, fontSize: 13),
              ),
              onTap: () async {
                Navigator.pop(ctx);
                _confirmDeleteSession(context, ref, session);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.fork_right,
                color: AppTheme.textSecondary,
                size: 20,
              ),
              title: const Text(
                'Fork Session',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 13),
              ),
              onTap: () async {
                Navigator.pop(ctx);
                try {
                  final sessionService = ref.read(sessionServiceProvider);
                  final forked = await sessionService.forkSession(
                    session.id,
                    directory: session.directory,
                  );
                  ref.invalidate(sessionsProvider);
                  ref.read(selectedSessionProvider.notifier).state = forked;
                  if (context.mounted) {
                    context.push('/chat/${forked.id}');
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to fork: $e')),
                    );
                  }
                }
              },
            ),
            if (session.share != null)
              ListTile(
                leading: const Icon(Icons.copy, color: AppTheme.info, size: 20),
                title: const Text(
                  'Copy Link',
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                ),
                subtitle: Text(
                  session.share!.url,
                  style: const TextStyle(
                    color: AppTheme.textTertiary,
                    fontSize: 10,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  Clipboard.setData(ClipboardData(text: session.share!.url));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Link copied to clipboard')),
                  );
                },
              ),
            ListTile(
              leading: Icon(
                session.share != null ? Icons.link_off : Icons.share,
                color: AppTheme.textSecondary,
                size: 20,
              ),
              title: Text(
                session.share != null ? 'Unshare' : 'Share',
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 13,
                ),
              ),
              onTap: () async {
                Navigator.pop(ctx);
                try {
                  final sessionService = ref.read(sessionServiceProvider);
                  if (session.share != null) {
                    await sessionService.unshareSession(
                      session.id,
                      directory: session.directory,
                    );
                  } else {
                    final updated = await sessionService.shareSession(
                      session.id,
                      directory: session.directory,
                    );
                    if (context.mounted && updated.share != null) {
                      Clipboard.setData(
                        ClipboardData(text: updated.share!.url),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Session shared! Link copied to clipboard',
                          ),
                        ),
                      );
                    }
                  }
                  ref.invalidate(sessionsProvider);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('Failed: $e')));
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteSession(
    BuildContext context,
    WidgetRef ref,
    dynamic session,
  ) async {
    final sessionTitle = session.title.isEmpty
        ? 'Untitled Session'
        : session.title;
    final selectedSession = ref.read(selectedSessionProvider);
    final isCurrentSession = selectedSession?.id == session.id;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text(
          'Delete Session?',
          style: TextStyle(color: AppTheme.textPrimary, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '"$sessionTitle"',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'This will permanently delete this session and all its messages.',
              style: TextStyle(color: AppTheme.textTertiary, fontSize: 12),
            ),
            if (isCurrentSession) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withValues(alpha: 0.1),
                  border: Border.all(
                    color: AppTheme.warning.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber,
                      size: 16,
                      color: AppTheme.warning,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'This is your current session. You will be redirected to the sessions list.',
                        style: TextStyle(color: AppTheme.warning, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppTheme.error),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final sessionService = ref.read(sessionServiceProvider);
      await sessionService.deleteSession(
        session.id,
        directory: session.directory,
      );
      await ref.read(activeSessionsProvider.notifier).clearActive(session.id);

      if (isCurrentSession) {
        ref.read(selectedSessionProvider.notifier).state = null;
      }

      ref.invalidate(sessionsProvider);

      if (isCurrentSession && context.mounted) {
        context.go('/sessions');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
      }
    }
  }

  String _formatTime(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return DateFormat('MMM d, HH:mm').format(dt);
  }
}
