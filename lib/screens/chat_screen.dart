import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/message.dart';
import '../models/permission_request.dart';
import '../models/session.dart';
import '../models/todo.dart';
import '../models/pty.dart';
import '../models/file_diff.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/chat_input.dart';
import '../widgets/file_changes_tree.dart';
import '../widgets/message_parts.dart';
import '../widgets/session_busy_indicator.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String? sessionId;

  const ChatScreen({super.key, this.sessionId});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final ScrollController _scrollController = ScrollController();
  StreamSubscription<Map<String, dynamic>>? _eventSub;
  ProviderSubscription<Session?>? _sessionSub;
  ProviderSubscription<AsyncValue<List<MessageWrapper>>>? _messagesSub;
  ProviderSubscription<String>? _sessionModeSub;
  bool _isBusy = false;
  bool _permissionDialogVisible = false;
  List<MessageWrapper> _cachedMessages = const [];
  String? _cachedSessionId;
  bool _hasLoadedMessages = false;
  String? _modelSyncSessionId;
  bool _didSyncModelFromMessages = false;
  bool _isSidebarOpen = false;
  bool _showScrollToBottom = false;
  bool _isUndoRedoInFlight = false;

  @override
  void initState() {
    super.initState();
    _subscribeToEvents();
    _listenToSessionChanges();
    _listenToMessageUpdates();
    _listenToSessionMode();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadPendingPermissions();
    });
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _sessionSub?.close();
    _messagesSub?.close();
    _sessionModeSub?.close();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final isNearBottom = position.pixels >= position.maxScrollExtent - 100;
    if (_showScrollToBottom == isNearBottom) {
      setState(() => _showScrollToBottom = !isNearBottom);
    }
  }

  void _subscribeToEvents() {
    final project = ref.read(selectedProjectProvider);
    if (project == null) return;

    final eventService = ref.read(eventServiceProvider);
    _eventSub = eventService.subscribe(directory: project.worktree).listen((
      event,
    ) {
      try {
        final type = event['type'] as String? ?? '';

        if (type == 'message.updated' ||
            type == 'message.removed' ||
            type == 'message.part.updated' ||
            type == 'message.part.removed') {
          ref.invalidate(messagesProvider);
        } else if (type == 'permission.asked') {
          final props = event['properties'];
          if (props is Map<String, dynamic>) {
            _handlePermissionAsked(props);
          }
        } else if (type == 'permission.updated' ||
            type == 'permission.replied') {
          _handlePermissionUpdated(event['properties']);
        } else if (type == 'session.updated') {
          ref.invalidate(sessionsProvider);
          final session = ref.read(selectedSessionProvider);
          if (session != null) {
            ref
                .read(sessionServiceProvider)
                .getSession(session.id, directory: session.directory)
                .then((updated) {
                  ref.read(selectedSessionProvider.notifier).state = updated;
                });
          }
        } else if (type == 'session.created') {
          ref.invalidate(sessionsProvider);
        } else if (type == 'session.deleted') {
          _handleSessionDeleted(event['properties']);
          ref.invalidate(sessionsProvider);
        } else if (type == 'session.status') {
          final props = event['properties'];
          if (!_isCurrentSessionEvent(props)) return;
          String? statusStr;
          if (props is Map<String, dynamic>) {
            final status = props['status'];
            if (status is Map<String, dynamic>) {
              statusStr = status['type']?.toString();
            } else {
              statusStr = status is String ? status : status?.toString();
            }
          }
          if (mounted) {
            setState(() {
              _isBusy = statusStr != null && statusStr != 'idle';
            });
          }
          if (_isBusy) {
            ref.invalidate(messagesProvider);
          }
        } else if (type == 'session.idle') {
          if (!_isCurrentSessionEvent(event['properties'])) return;
          if (mounted) {
            setState(() => _isBusy = false);
          }
          ref.invalidate(messagesProvider);
        } else if (type == 'session.compacted') {
          if (!_isCurrentSessionEvent(event['properties'])) return;
          ref.invalidate(messagesProvider);
        } else if (type == 'session.error') {
          _handleSessionError(event['properties']);
        } else if (type == 'session.diff') {
          _handleSessionDiff(event['properties']);
        } else if (type == 'todo.updated') {
          _handleTodoUpdated(event['properties']);
        } else if (type == 'vcs.branch.updated') {
          _handleBranchUpdated(event['properties']);
        } else if (type == 'tui.prompt.append') {
          _handlePromptAppend(event['properties']);
        } else if (type == 'tui.command.execute') {
          _handleCommandExecuted(event['properties']);
        } else if (type == 'command.executed') {
          _handleCommandExecuted(event['properties']);
        } else if (type == 'tui.toast.show') {
          _handleToastEvent(event['properties']);
        } else if (type == 'pty.created') {
          _handlePtyCreated(event['properties']);
        } else if (type == 'pty.updated') {
          _handlePtyUpdated(event['properties']);
        } else if (type == 'pty.exited') {
          _handlePtyExited(event['properties']);
        } else if (type == 'pty.deleted') {
          _handlePtyDeleted(event['properties']);
        }
      } catch (e) {
        debugPrint('[ChatScreen] Event error: $e\nRaw event: $event');
      }
    });
  }

  void _listenToSessionChanges() {
    _sessionSub = ref.listenManual<Session?>(selectedSessionProvider, (
      prev,
      next,
    ) {
      if (next != null && (prev == null || prev.id != next.id)) {
        _resetSessionState(next.id);
        ref.read(todosProvider.notifier).clear();
        ref.read(sessionErrorProvider.notifier).clear();
        ref.read(ptyProvider.notifier).clear();
        ref.read(sessionDiffProvider.notifier).clear();
        ref.read(vcsBranchProvider.notifier).state = null;
        _loadProjectModel(next.projectID, next.id);
        _loadSessionModel(next.id);
        _loadSessionMode(next.id);
        _loadPendingPermissions();
        _loadTodos(next);
        _loadSessionDiff(next);
        _loadVcsBranch(next);
      }
    });
  }

  void _listenToSessionMode() {
    _sessionModeSub = ref.listenManual<String>(sessionModeProvider, (
      prev,
      next,
    ) {
      final session = ref.read(selectedSessionProvider);
      if (session == null) return;
      if (prev == next) return;
      ref.read(preferencesServiceProvider).saveSessionMode(session.id, next);
    });
  }

  void _listenToMessageUpdates() {
    _messagesSub = ref.listenManual<AsyncValue<List<MessageWrapper>>>(
      messagesProvider,
      (prev, next) {
        final session = ref.read(selectedSessionProvider);
        final nextMessages = next.valueOrNull;
        if (session != null && nextMessages != null) {
          _updateCachedMessages(session.id, nextMessages);
          _syncSelectedModelFromMessages(session, nextMessages);
        }

        final prevLength = prev?.valueOrNull?.length ?? 0;
        final nextLength = next.valueOrNull?.length ?? 0;
        if (nextLength > prevLength) {
          _scrollToBottom();
        }
      },
    );
  }

  bool _isCurrentSessionEvent(dynamic props) {
    if (props is! Map<String, dynamic>) return false;
    final sessionId = props['sessionID']?.toString();
    final session = ref.read(selectedSessionProvider);
    if (session == null || sessionId == null) return false;
    return sessionId == session.id;
  }

  void _handleTodoUpdated(dynamic props) {
    if (props is! Map<String, dynamic>) return;
    final session = ref.read(selectedSessionProvider);
    if (session == null) return;
    final sessionId = props['sessionID']?.toString();
    if (sessionId != session.id) return;
    final todosRaw = props['todos'];
    if (todosRaw is! List) return;
    final todos = todosRaw
        .whereType<Map<String, dynamic>>()
        .map((item) => Todo.fromJson(item))
        .toList();
    ref.read(todosProvider.notifier).setTodos(session.id, todos);
  }

  void _handleBranchUpdated(dynamic props) {
    if (props is! Map<String, dynamic>) return;
    final branch = props['branch']?.toString();
    ref.read(vcsBranchProvider.notifier).state = branch;
  }

  void _handlePromptAppend(dynamic props) {
    if (props is! Map<String, dynamic>) return;
    final text = props['text']?.toString();
    if (text == null || text.isEmpty) return;
    if (!mounted) return;
    ChatInput.appendText(context, text);
  }

  void _handleCommandExecuted(dynamic props) {
    if (props is! Map<String, dynamic>) return;
    final name = props['name']?.toString() ?? props['command']?.toString();
    if (name == null || name.isEmpty) return;
    final args = props['arguments']?.toString();
    if (mounted) {
      final label = args != null && args.isNotEmpty
          ? 'Command executed: $name $args'
          : 'Command executed: $name';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(label)));
    }
  }

  void _handleToastEvent(dynamic props) {
    if (!mounted) return;
    if (props is! Map<String, dynamic>) return;
    final message = props['message']?.toString();
    if (message == null || message.isEmpty) return;
    final title = props['title']?.toString();
    final variant = props['variant']?.toString() ?? 'info';
    final durationMs = (props['duration'] as num?)?.toInt();
    final color = _toastColor(variant);
    final snackText = title != null && title.isNotEmpty
        ? '$title: $message'
        : message;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(snackText),
        backgroundColor: color,
        duration: Duration(milliseconds: durationMs ?? 2800),
      ),
    );
  }

  void _handlePtyCreated(dynamic props) {
    if (props is! Map<String, dynamic>) return;
    if (!_isCurrentSessionEvent(props)) return;
    final info = props['info'];
    if (info is! Map<String, dynamic>) return;
    ref.read(ptyProvider.notifier).upsert(PtyInfo.fromJson(info));
  }

  void _handlePtyUpdated(dynamic props) {
    if (props is! Map<String, dynamic>) return;
    if (!_isCurrentSessionEvent(props)) return;
    final info = props['info'];
    if (info is! Map<String, dynamic>) return;
    ref.read(ptyProvider.notifier).upsert(PtyInfo.fromJson(info));
  }

  void _handlePtyExited(dynamic props) {
    if (props is! Map<String, dynamic>) return;
    if (!_isCurrentSessionEvent(props)) return;
    final id = props['id']?.toString();
    if (id == null || id.isEmpty) return;
    final exitCode = (props['exitCode'] as num?)?.toInt() ?? 0;
    ref.read(ptyProvider.notifier).updateExit(id, exitCode);
  }

  void _handlePtyDeleted(dynamic props) {
    if (props is! Map<String, dynamic>) return;
    if (!_isCurrentSessionEvent(props)) return;
    final id = props['id']?.toString();
    if (id == null || id.isEmpty) return;
    ref.read(ptyProvider.notifier).remove(id);
  }

  void _handleSessionError(dynamic props) {
    if (props is! Map<String, dynamic>) return;
    if (!_isCurrentSessionEvent(props)) return;
    final sessionId = props['sessionID']?.toString();
    final error = props['error'];
    String? message;
    String? name;
    if (error is Map<String, dynamic>) {
      name = error['name']?.toString();
      final data = error['data'];
      if (data is Map<String, dynamic>) {
        message = data['message']?.toString();
      }
    }
    ref
        .read(sessionErrorProvider.notifier)
        .setError(sessionID: sessionId, message: message, name: name);
    if (mounted) {
      final display = message ?? name ?? 'Session error';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(display), backgroundColor: AppTheme.error),
      );
    }
  }

  void _handleSessionDiff(dynamic props) {
    if (props is! Map<String, dynamic>) return;
    if (!_isCurrentSessionEvent(props)) return;
    final diffsRaw = props['diff'];
    if (diffsRaw is! List) return;
    final diffs = diffsRaw
        .whereType<Map<String, dynamic>>()
        .map((item) => FileDiff.fromJson(item))
        .toList();
    final session = ref.read(selectedSessionProvider);
    if (session == null) return;
    ref.read(sessionDiffProvider.notifier).setDiff(session.id, diffs);
  }

  void _handleSessionDeleted(dynamic props) {
    if (props is! Map<String, dynamic>) return;
    final info = props['info'];
    if (info is! Map<String, dynamic>) return;
    final deletedId = info['id']?.toString();
    if (deletedId == null || deletedId.isEmpty) return;
    final session = ref.read(selectedSessionProvider);
    if (session != null && session.id == deletedId) {
      ref.read(selectedSessionProvider.notifier).state = null;
      if (mounted) {
        context.go('/sessions');
      }
    }
  }

  Color _toastColor(String variant) {
    return switch (variant) {
      'success' => AppTheme.success,
      'warning' => AppTheme.warning,
      'error' => AppTheme.error,
      _ => AppTheme.info,
    };
  }

  void _resetSessionState(String sessionId) {
    if (!mounted) return;
    setState(() {
      _cachedSessionId = sessionId;
      _cachedMessages = const [];
      _hasLoadedMessages = false;
      _permissionDialogVisible = false;
    });
    _modelSyncSessionId = sessionId;
    _didSyncModelFromMessages = false;
  }

  Future<void> _loadPendingPermissions() async {
    final project = ref.read(selectedProjectProvider);
    final session = ref.read(selectedSessionProvider);
    if (project == null || session == null) return;
    if (_permissionDialogVisible) return;
    try {
      final permissionService = ref.read(permissionServiceProvider);
      final pending = await permissionService.listPending(
        directory: project.worktree,
      );
      if (!mounted || pending.isEmpty) return;
      final matches = pending
          .where((request) => request.sessionID == session.id)
          .toList();
      if (matches.isEmpty) return;
      await _showPermissionDialog(matches.first);
    } catch (_) {
      // ignore permission polling failures
    }
  }

  void _handlePermissionAsked(Map<String, dynamic> props) {
    final session = ref.read(selectedSessionProvider);
    if (session == null) return;
    if (_permissionDialogVisible) return;
    if (props['sessionID'] != session.id) return;
    _showPermissionDialog(PermissionRequest.fromJson(props));
  }

  void _handlePermissionUpdated(dynamic props) {
    if (props is! Map<String, dynamic>) return;
    final session = ref.read(selectedSessionProvider);
    if (session == null) return;
    if (props['sessionID'] != session.id) return;
    _loadPendingPermissions();
  }

  String _formatPermissionTitle(PermissionRequest request) {
    final permission = request.permission.trim();
    if (permission.isEmpty) return 'Permission requested';
    final parts = permission.split('.');
    if (parts.isEmpty) return 'Permission requested';
    final label = parts.last.replaceAll('_', ' ');
    return 'Allow ${label.toUpperCase()}?';
  }

  String _buildPermissionDescription(PermissionRequest request) {
    final buffer = StringBuffer();
    if (request.patterns.isNotEmpty) {
      buffer.write('Patterns: ${request.patterns.join(', ')}');
    }
    if (request.always.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.write('\n');
      buffer.write('Always: ${request.always.join(', ')}');
    }
    return buffer.isEmpty
        ? 'Assistant needs your approval.'
        : buffer.toString();
  }

  Future<void> _respondToPermission(
    PermissionRequest request,
    String reply,
  ) async {
    final project = ref.read(selectedProjectProvider);
    if (project == null) return;
    try {
      final permissionService = ref.read(permissionServiceProvider);
      await permissionService.reply(
        request.id,
        reply: reply,
        directory: project.worktree,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Permission failed: $e')));
      }
    }
  }

  Future<void> _showPermissionDialog(PermissionRequest request) async {
    if (!mounted) return;
    _permissionDialogVisible = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 18),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatPermissionTitle(request),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _buildPermissionDescription(request),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          Navigator.of(context).pop();
                          await _respondToPermission(request, 'reject');
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.error,
                          side: const BorderSide(color: AppTheme.error),
                        ),
                        child: const Text(
                          'DENY',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          Navigator.of(context).pop();
                          await _respondToPermission(request, 'once');
                        },
                        child: const Text(
                          'ONCE',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          Navigator.of(context).pop();
                          await _respondToPermission(request, 'always');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accent,
                          foregroundColor: AppTheme.textPrimary,
                        ),
                        child: const Text(
                          'ALWAYS',
                          style: TextStyle(fontSize: 11),
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
    );
    if (mounted) {
      setState(() {
        _permissionDialogVisible = false;
      });
      _loadPendingPermissions();
    }
  }

  void _updateCachedMessages(String sessionId, List<MessageWrapper> messages) {
    if (!mounted) return;
    final shouldUpdate =
        _cachedSessionId != sessionId || !identical(_cachedMessages, messages);
    if (shouldUpdate || !_hasLoadedMessages) {
      setState(() {
        _cachedSessionId = sessionId;
        _cachedMessages = messages;
        _hasLoadedMessages = true;
      });
    }
  }

  void _syncSelectedModelFromMessages(
    Session session,
    List<MessageWrapper> messages,
  ) {
    if (_modelSyncSessionId != session.id) {
      _modelSyncSessionId = session.id;
      _didSyncModelFromMessages = false;
    }
    if (_didSyncModelFromMessages || messages.isEmpty) return;

    String? providerId;
    String? modelId;

    for (var i = messages.length - 1; i >= 0; i--) {
      final info = messages[i].info;
      if (info is AssistantMessageInfo) {
        if (info.providerID.isNotEmpty && info.modelID.isNotEmpty) {
          providerId = info.providerID;
          modelId = info.modelID;
          break;
        }
      } else if (info is UserMessageInfo) {
        final model = info.model;
        if (model != null && model.providerID.isNotEmpty) {
          providerId = model.providerID;
          modelId = model.modelID;
          break;
        }
      }
    }

    if (providerId == null || modelId == null) return;

    final current = ref.read(selectedModelProvider);
    if (current == null ||
        current['providerID'] != providerId ||
        current['modelID'] != modelId) {
      ref.read(selectedModelProvider.notifier).state = {
        'providerID': providerId,
        'modelID': modelId,
      };
      ref
          .read(preferencesServiceProvider)
          .saveSessionModel(session.id, providerId, modelId);
    }
    _didSyncModelFromMessages = true;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Widget _buildMessagesPanel({
    required List<MessageWrapper> displayMessages,
    required AsyncValue<List<MessageWrapper>> messagesAsync,
    required bool isInitialLoading,
    required String mode,
  }) {
    final session = ref.watch(selectedSessionProvider);
    final statusAsync = ref.watch(sessionStatusProvider);
    final isSessionBusy = statusAsync.maybeWhen(
      data: (status) {
        if (session == null) return false;
        final info = status[session.id];
        if (info is Map<String, dynamic>) {
          return info['type'] == 'busy' || info['type'] == 'retry';
        }
        if (info is String) {
          return info == 'busy' || info == 'retry';
        }
        return false;
      },
      orElse: () => false,
    );

    final busyLabel = () {
      if (session == null) return 'Session busy';
      final info = statusAsync.valueOrNull?[session.id];
      if (info is Map<String, dynamic>) {
        final message = info['message']?.toString();
        final attempt = info['attempt'];
        if (message != null && message.isNotEmpty) {
          return message;
        }
        if (attempt != null) {
          return 'Retrying (attempt $attempt)';
        }
      }
      return 'Session busy';
    }();

    if (messagesAsync.hasError && displayMessages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Error: ${messagesAsync.error}',
              style: const TextStyle(
                color: AppTheme.textTertiary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => ref.invalidate(messagesProvider),
              child: const Text('RETRY'),
            ),
          ],
        ),
      );
    }

    if (displayMessages.isEmpty) {
      if (isInitialLoading && !_isBusy) {
        return const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      }

      if (_isBusy || isSessionBusy) {
        return Column(
          children: [
            SessionBusyIndicator(label: busyLabel),
            const Spacer(),
          ],
        );
      }

      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.border),
              ),
              child: Icon(Icons.terminal, size: 32, color: AppTheme.accent),
            ),
            const SizedBox(height: 16),
            const Text(
              'Start a conversation',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 6),
            Text(
              'Mode: ${mode.toUpperCase()}',
              style: TextStyle(
                color: mode == 'plan' ? AppTheme.info : AppTheme.accent,
                fontSize: 11,
              ),
            ),
          ],
        ),
      );
    }

    final listWidget = ListView.builder(
      controller: _scrollController,
      cacheExtent: 800,
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: displayMessages.length,
      itemBuilder: (context, index) {
        final msg = displayMessages[index];
        return RepaintBoundary(
          child: KeyedSubtree(
            key: ValueKey(msg.info.id),
            child: _buildMessage(msg),
          ),
        );
      },
    );

    Widget listWithButton = Stack(
      children: [
        listWidget,
        if (_showScrollToBottom)
          Positioned(
            right: 12,
            bottom: 12,
            child: Material(
              color: AppTheme.surface,
              shape: const CircleBorder(
                side: BorderSide(color: AppTheme.border),
              ),
              child: InkWell(
                onTap: _scrollToBottom,
                customBorder: const CircleBorder(),
                child: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.keyboard_arrow_down,
                    size: 20,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    return listWithButton;
  }

  Widget _buildSidebar({required SessionErrorState errorState}) {
    final todosState = ref.watch(todosProvider);
    final ptyState = ref.watch(ptyProvider);
    final ptys = ptyState.items.values.toList()
      ..sort((a, b) {
        final titleA = a.title.isNotEmpty ? a.title : a.command;
        final titleB = b.title.isNotEmpty ? b.title : b.command;
        return titleA.compareTo(titleB);
      });
    final tabs = const [
      Tab(text: 'CHANGES'),
      Tab(text: 'TODOS'),
      Tab(text: 'PTY'),
    ];

    return Container(
      width: 280,
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(left: BorderSide(color: AppTheme.border)),
      ),
      child: Column(
        children: [
          if (errorState.message != null || errorState.name != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.error.withValues(alpha: 0.15),
                border: Border(
                  bottom: BorderSide(
                    color: AppTheme.error.withValues(alpha: 0.4),
                  ),
                ),
              ),
              child: Text(
                errorState.message ?? errorState.name ?? 'Session error',
                style: const TextStyle(
                  fontSize: 10,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
          Expanded(
            child: DefaultTabController(
              length: tabs.length,
              child: Column(
                children: [
                  TabBar(
                    tabs: tabs,
                    labelColor: AppTheme.textPrimary,
                    unselectedLabelColor: AppTheme.textTertiary,
                    indicatorColor: AppTheme.accent,
                    labelStyle: const TextStyle(fontSize: 10, letterSpacing: 1),
                  ),
                  Expanded(
                    child: TabBarView(
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _buildChangesTab(),
                        _buildTodosTab(todosState),
                        _buildPtyTab(ptys),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarToggle() {
    final todos = ref.watch(todosProvider).todos;
    final pendingCount = todos.where((todo) {
      final status = todo.status.toLowerCase();
      return status == 'in_progress' ||
          status == 'inprogress' ||
          status == 'pending' ||
          status == 'todo';
    }).length;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: Icon(
            _isSidebarOpen ? Icons.view_sidebar : Icons.view_sidebar_outlined,
            size: 20,
          ),
          onPressed: () {
            setState(() => _isSidebarOpen = !_isSidebarOpen);
          },
          tooltip: 'Sidebar',
        ),
        if (pendingCount > 0)
          Positioned(
            right: 4,
            top: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.warning,
                border: Border.all(color: AppTheme.border),
              ),
              child: Text(
                pendingCount > 99 ? '99+' : pendingCount.toString(),
                style: const TextStyle(
                  fontSize: 8,
                  color: AppTheme.background,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildChangesTab() {
    final diffState = ref.watch(sessionDiffProvider);
    if (diffState.isLoading) {
      return const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (diffState.error != null) {
      return Center(
        child: Text(
          'Diff error: ${diffState.error}',
          style: const TextStyle(color: AppTheme.textTertiary, fontSize: 11),
          textAlign: TextAlign.center,
        ),
      );
    }

    return FileChangesTree(diffs: diffState.diffs);
  }

  Widget _buildTodosTab(TodosState todosState) {
    if (todosState.isLoading) {
      return const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (todosState.todos.isEmpty) {
      return const Center(
        child: Text(
          'No todos',
          style: TextStyle(color: AppTheme.textTertiary, fontSize: 11),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: todosState.todos.length,
      separatorBuilder: (_, __) => const Divider(height: 16),
      itemBuilder: (context, index) {
        final todo = todosState.todos[index];
        final status = todo.status.toUpperCase();
        final priority = todo.priority.toUpperCase();

        // Determine status color based on status value
        Color statusColor;
        switch (todo.status.toLowerCase()) {
          case 'in_progress':
          case 'inprogress':
          case 'pending':
            statusColor = AppTheme.warning;
          case 'done':
          case 'completed':
          case 'complete':
            statusColor = AppTheme.success;
          default:
            statusColor = AppTheme.textTertiary;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              todo.content,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  status,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  priority,
                  style: const TextStyle(
                    color: AppTheme.textTertiary,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildPtyTab(List<PtyInfo> ptys) {
    if (ptys.isEmpty) {
      return const Center(
        child: Text(
          'No ptys',
          style: TextStyle(color: AppTheme.textTertiary, fontSize: 11),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: ptys.length,
      separatorBuilder: (_, __) => const Divider(height: 16),
      itemBuilder: (context, index) {
        final pty = ptys[index];
        final title = pty.title.isNotEmpty ? pty.title : pty.command;
        final exitCode = pty.exitCode;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              pty.cwd,
              style: const TextStyle(
                color: AppTheme.textTertiary,
                fontSize: 10,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: pty.status == 'running'
                        ? AppTheme.success
                        : AppTheme.textTertiary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  pty.status.toUpperCase(),
                  style: const TextStyle(
                    color: AppTheme.textTertiary,
                    fontSize: 9,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'PID ${pty.pid}',
                  style: const TextStyle(
                    color: AppTheme.textTertiary,
                    fontSize: 9,
                  ),
                ),
                if (exitCode != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    'EXIT $exitCode',
                    style: const TextStyle(
                      color: AppTheme.textTertiary,
                      fontSize: 9,
                    ),
                  ),
                ],
              ],
            ),
          ],
        );
      },
    );
  }

  Future<void> _sendMessage(
    String text, {
    List<Map<String, dynamic>>? fileParts,
  }) async {
    final session = ref.read(selectedSessionProvider);
    if (session == null) return;

    final model = ref.read(activeModelProvider);
    final mode = ref.read(sessionModeProvider);

    final parts = <Map<String, dynamic>>[];

    if (fileParts != null) {
      parts.addAll(fileParts);
    }

    parts.add({'type': 'text', 'text': text});

    if (model == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No model selected. Pick a model first.'),
          ),
        );
      }
      return;
    }

    try {
      setState(() => _isBusy = true);

      final messageService = ref.read(messageServiceProvider);
      await messageService.sendMessageAsync(
        session.id,
        parts: parts,
        providerID: model['providerID'],
        modelID: model['modelID'],
        agent: mode,
        directory: session.directory,
      );

      ref.invalidate(messagesProvider);
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        setState(() => _isBusy = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send: $e')));
      }
    }
  }

  Future<void> _sendCommand(String command, String arguments) async {
    final session = ref.read(selectedSessionProvider);
    if (session == null) return;
    final mode = ref.read(sessionModeProvider);

    try {
      setState(() => _isBusy = true);

      final messageService = ref.read(messageServiceProvider);
      await messageService.sendCommand(
        session.id,
        command: command,
        arguments: arguments,
        agent: mode,
        directory: session.directory,
      );

      ref.invalidate(messagesProvider);
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        setState(() => _isBusy = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  Future<void> _abortSession() async {
    final session = ref.read(selectedSessionProvider);
    if (session == null) return;

    try {
      final sessionService = ref.read(sessionServiceProvider);
      await sessionService.abortSession(
        session.id,
        directory: session.directory,
      );
      setState(() => _isBusy = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to abort: $e')));
      }
    }
  }

  Future<void> _loadSessionModel(String sessionId) async {
    final prefs = ref.read(preferencesServiceProvider);
    final savedModel = await prefs.getSessionModel(sessionId);
    // Logic:
    // If we have a saved model for this session, set it as selected.
    // If NOT, we ensure selectedModelProvider is null so it falls back to default.
    // IMPORTANT: We only set state if it's different to avoid loops if this is called repeatedly.
    // But since this is a one-off load, we can just set it.

    // However, if the user explicitly cleared it in this session before (in memory), we might overwrite?
    // But since _loadSessionModel is intended to be called on session switch, it's fine.

    final current = ref.read(selectedModelProvider);
    if (savedModel == null) {
      if (current != null) {
        ref.read(selectedModelProvider.notifier).state = null;
      }
      return;
    }
    if (current == null ||
        current['providerID'] != savedModel['providerID'] ||
        current['modelID'] != savedModel['modelID']) {
      ref.read(selectedModelProvider.notifier).state = savedModel;
    }
  }

  Future<void> _loadProjectModel(String projectId, String sessionId) async {
    await ref.read(projectModelProvider.notifier).load(projectId);
    final projectModel = ref.read(projectModelProvider).model;
    if (projectModel == null) return;
    final prefs = ref.read(preferencesServiceProvider);
    final savedSessionModel = await prefs.getSessionModel(sessionId);
    if (savedSessionModel != null) return;
    final current = ref.read(selectedModelProvider);
    if (current == null) {
      ref.read(selectedModelProvider.notifier).state = projectModel;
    }
  }

  Future<void> _loadSessionMode(String sessionId) async {
    final prefs = ref.read(preferencesServiceProvider);
    final savedMode = await prefs.getSessionMode(sessionId);
    if (savedMode == null) return;
    final current = ref.read(sessionModeProvider);
    if (current != savedMode) {
      ref.read(sessionModeProvider.notifier).state = savedMode;
    }
  }

  Future<void> _loadTodos(Session session) async {
    await ref
        .read(todosProvider.notifier)
        .loadTodos(session.id, directory: session.directory);
  }

  Future<void> _loadSessionDiff(Session session) async {
    await ref
        .read(sessionDiffProvider.notifier)
        .loadDiff(session.id, directory: session.directory);
  }

  Future<void> _loadVcsBranch(Session session) async {
    final project = ref.read(selectedProjectProvider);
    if (project == null) return;
    try {
      final info = await ref
          .read(appServiceProvider)
          .getVcsInfo(directory: project.worktree);
      ref.read(vcsBranchProvider.notifier).state = info.branch;
    } catch (_) {
      // ignore vcs failures
    }
  }

  Future<void> _revertMessage(MessageWrapper msg) async {
    final session = ref.read(selectedSessionProvider);
    if (session == null) return;
    if (_isUndoRedoInFlight) return;
    setState(() => _isUndoRedoInFlight = true);
    try {
      final sessionService = ref.read(sessionServiceProvider);
      final updated = await sessionService.revertSession(
        session.id,
        messageID: msg.info.id,
        directory: session.directory,
      );
      ref.read(selectedSessionProvider.notifier).state = updated;
      ref.invalidate(messagesProvider);
      ref.read(sessionDiffProvider.notifier).clear();
      await _loadSessionDiff(updated);
      await _loadTodos(updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message effects reverted.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Undo failed: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isUndoRedoInFlight = false);
      }
    }
  }

  Future<void> _unrevertSession(Session session) async {
    if (_isUndoRedoInFlight) return;
    setState(() => _isUndoRedoInFlight = true);
    try {
      final sessionService = ref.read(sessionServiceProvider);
      final updated = await sessionService.unrevertSession(
        session.id,
        directory: session.directory,
      );
      ref.read(selectedSessionProvider.notifier).state = updated;
      ref.invalidate(messagesProvider);
      ref.read(sessionDiffProvider.notifier).clear();
      await _loadSessionDiff(updated);
      await _loadTodos(updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message effects restored.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Redo failed: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isUndoRedoInFlight = false);
      }
    }
  }

  Widget _buildMessageActions({
    required bool canUndo,
    required bool canRedo,
    required VoidCallback onUndo,
    required VoidCallback onRedo,
  }) {
    return Wrap(
      spacing: 4,
      children: [
        IconButton(
          icon: const Icon(Icons.undo, size: 14),
          onPressed: canUndo ? onUndo : null,
          tooltip: 'Undo message effects',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          visualDensity: VisualDensity.compact,
        ),
        IconButton(
          icon: const Icon(Icons.redo, size: 14),
          onPressed: canRedo ? onRedo : null,
          tooltip: 'Redo message effects',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(selectedSessionProvider);
    final messagesAsync = ref.watch(messagesProvider);
    final mode = ref.watch(sessionModeProvider);
    final activeModel = ref.watch(activeModelProvider);
    final branch = ref.watch(vcsBranchProvider);
    final errorState = ref.watch(sessionErrorProvider);

    final messages = messagesAsync.valueOrNull ?? const <MessageWrapper>[];
    final displayMessages = _cachedMessages.isNotEmpty
        ? _cachedMessages
        : messages;
    final isInitialLoading = messagesAsync.isLoading && !_hasLoadedMessages;

    if (session == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, size: 20),
            onPressed: () => context.go('/sessions'),
          ),
        ),
        body: const Center(
          child: Text(
            'No session selected',
            style: TextStyle(color: AppTheme.textTertiary),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 20),
          onPressed: () => context.go('/sessions'),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              session.title.isEmpty ? 'New Session' : session.title,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  color: _isBusy ? AppTheme.warning : AppTheme.success,
                ),
                const SizedBox(width: 4),
                Text(
                  _isBusy
                      ? (mode == 'plan' ? 'Planning...' : 'Building...')
                      : 'Ready${(activeModel != null) ? " • ${activeModel['modelID']}" : ""}',
                  style: TextStyle(
                    fontSize: 10,
                    color: _isBusy ? AppTheme.warning : AppTheme.textTertiary,
                  ),
                ),
                if (branch != null && branch.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    '• $branch',
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppTheme.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
        actions: [
          GestureDetector(
            onTap: () {
              final newMode = mode == 'plan' ? 'build' : 'plan';
              ref.read(sessionModeProvider.notifier).state = newMode;
            },
            child: Container(
              margin: const EdgeInsets.only(right: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: mode == 'plan'
                    ? AppTheme.info.withValues(alpha: 0.15)
                    : AppTheme.accent.withValues(alpha: 0.15),
                border: Border.all(
                  color: mode == 'plan' ? AppTheme.info : AppTheme.accent,
                ),
              ),
              child: Text(
                mode.toUpperCase(),
                style: TextStyle(
                  color: mode == 'plan' ? AppTheme.info : AppTheme.accent,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
          _buildSidebarToggle(),
          IconButton(
            icon: const Icon(Icons.swap_horiz, size: 20),
            onPressed: () {
              context.push('/models', extra: {'mode': 'session'});
            },
            tooltip: 'Models',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: _buildMessagesPanel(
                    displayMessages: displayMessages,
                    messagesAsync: messagesAsync,
                    isInitialLoading: isInitialLoading,
                    mode: mode,
                  ),
                ),
                if (_isSidebarOpen) _buildSidebar(errorState: errorState),
              ],
            ),
          ),
          if (_isBusy)
            Container(
              width: double.infinity,
              height: 2,
              color: AppTheme.border,
              child: LinearProgressIndicator(
                backgroundColor: AppTheme.border,
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accent),
              ),
            ),
          ChatInput(
            onSendMessage: _sendMessage,
            onSendCommand: _sendCommand,
            onStop: _abortSession,
            isBusy: _isBusy,
            enabled: !_isBusy,
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(MessageWrapper msg) {
    final isUser = msg.info.role == 'user';
    final session = ref.watch(selectedSessionProvider);
    final isAssistant = msg.info.role == 'assistant';
    final canUndo =
        isAssistant && !_isBusy && !_isUndoRedoInFlight && session != null;
    final canRedo =
        isAssistant &&
        !_isBusy &&
        !_isUndoRedoInFlight &&
        session?.revert?.messageID == msg.info.id;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Role header
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  width: 4,
                  height: 12,
                  color: isUser ? AppTheme.info : AppTheme.accent,
                ),
                Text(
                  isUser ? 'YOU' : 'ASSISTANT',
                  style: TextStyle(
                    color: isUser ? AppTheme.info : AppTheme.accent,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                if (!isUser && msg.info is AssistantMessageInfo)
                  Text(
                    (msg.info as AssistantMessageInfo).modelID,
                    style: const TextStyle(
                      color: AppTheme.textTertiary,
                      fontSize: 9,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (isAssistant)
                  _buildMessageActions(
                    canUndo: canUndo,
                    canRedo: canRedo,
                    onUndo: () => _revertMessage(msg),
                    onRedo: session == null
                        ? () {}
                        : () => _unrevertSession(session),
                  ),
              ],
            ),
          ),
          // Parts
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: isUser ? AppTheme.userBubble : AppTheme.assistantBubble,
              border: Border(
                left: BorderSide(
                  color: isUser
                      ? AppTheme.info.withValues(alpha: 0.3)
                      : AppTheme.accent.withValues(alpha: 0.3),
                  width: 2,
                ),
              ),
            ),
            padding: const EdgeInsets.all(12),
            child: MessagePartsWidget(parts: msg.parts, isUser: isUser),
          ),
          // Cost info for assistant
          if (!isUser && msg.info is AssistantMessageInfo) ...[
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 6),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text(
                    '\$${(msg.info as AssistantMessageInfo).cost.toStringAsFixed(4)}',
                    style: const TextStyle(
                      color: AppTheme.textTertiary,
                      fontSize: 9,
                    ),
                  ),
                  Text(
                    '${(msg.info as AssistantMessageInfo).tokens.input + (msg.info as AssistantMessageInfo).tokens.output} tokens',
                    style: const TextStyle(
                      color: AppTheme.textTertiary,
                      fontSize: 9,
                    ),
                  ),
                  if ((msg.info as AssistantMessageInfo).mode.isNotEmpty)
                    Text(
                      (msg.info as AssistantMessageInfo).mode.toUpperCase(),
                      style: const TextStyle(
                        color: AppTheme.textTertiary,
                        fontSize: 9,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
