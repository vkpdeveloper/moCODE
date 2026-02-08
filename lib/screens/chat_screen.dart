import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/message.dart';
import '../models/session.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/chat_input.dart';
import '../widgets/message_parts.dart';

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
  ProviderSubscription<Map<String, String>?>? _activeModelSub;
  ProviderSubscription<String>? _sessionModeSub;
  bool _isBusy = false;
  List<MessageWrapper> _cachedMessages = const [];
  String? _cachedSessionId;
  bool _hasLoadedMessages = false;
  String? _modelSyncSessionId;
  bool _didSyncModelFromMessages = false;
  String? _defaultSeedSessionId;
  bool _didSeedDefaultModel = false;

  @override
  void initState() {
    super.initState();
    _subscribeToEvents();
    _listenToSessionChanges();
    _listenToMessageUpdates();
    _listenToActiveModel();
    _listenToSessionMode();
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _sessionSub?.close();
    _messagesSub?.close();
    _activeModelSub?.close();
    _sessionModeSub?.close();
    _scrollController.dispose();
    super.dispose();
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

        if (type.startsWith('message.')) {
          ref.invalidate(messagesProvider);
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
        } else if (type == 'session.status') {
          final props = event['properties'];
          String? statusStr;
          if (props is Map<String, dynamic>) {
            final status = props['status'];
            statusStr = status is String ? status : status?.toString();
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
          if (mounted) {
            setState(() => _isBusy = false);
          }
          ref.invalidate(messagesProvider);
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
        _loadSessionModel(next.id);
        _loadSessionMode(next.id);
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

  void _listenToActiveModel() {
    _activeModelSub = ref.listenManual<Map<String, String>?>(
      activeModelProvider,
      (prev, next) {
        if (next == null) return;
        final providerId = next['providerID'];
        final modelId = next['modelID'];
        if (providerId == null || providerId.isEmpty) return;
        if (modelId == null || modelId.isEmpty) return;
        final session = ref.read(selectedSessionProvider);
        if (session == null) return;
        if (_defaultSeedSessionId != session.id) {
          _defaultSeedSessionId = session.id;
          _didSeedDefaultModel = false;
        }
        if (_didSeedDefaultModel || _didSyncModelFromMessages) return;
        if (_cachedMessages.isNotEmpty) return;
        final selected = ref.read(selectedModelProvider);
        if (selected != null) return;

        ref.read(selectedModelProvider.notifier).state = {
          'providerID': providerId,
          'modelID': modelId,
        };
        ref
            .read(preferencesServiceProvider)
            .saveSessionModel(session.id, providerId, modelId);
        _didSeedDefaultModel = true;
      },
    );
  }

  void _resetSessionState(String sessionId) {
    if (!mounted) return;
    setState(() {
      _cachedSessionId = sessionId;
      _cachedMessages = const [];
      _hasLoadedMessages = false;
    });
    _modelSyncSessionId = sessionId;
    _didSyncModelFromMessages = false;
    _defaultSeedSessionId = sessionId;
    _didSeedDefaultModel = false;
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

  Future<void> _loadSessionMode(String sessionId) async {
    final prefs = ref.read(preferencesServiceProvider);
    final savedMode = await prefs.getSessionMode(sessionId);
    if (savedMode == null) return;
    final current = ref.read(sessionModeProvider);
    if (current != savedMode) {
      ref.read(sessionModeProvider.notifier).state = savedMode;
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(selectedSessionProvider);
    final messagesAsync = ref.watch(messagesProvider);
    final mode = ref.watch(sessionModeProvider);
    final activeModel = ref.watch(activeModelProvider);

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
                      ? 'Processing...'
                      : 'Ready${(activeModel != null) ? " • ${activeModel['modelID']}" : ""}',
                  style: TextStyle(
                    fontSize: 10,
                    color: _isBusy ? AppTheme.warning : AppTheme.textTertiary,
                  ),
                ),
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

          IconButton(
            icon: const Icon(Icons.swap_horiz, size: 20),
            onPressed: () {
              context.push(
                '/models',
                extra: {
                  'onSelection': (String p, String m) {
                    ref.read(selectedModelProvider.notifier).state = {
                      'providerID': p,
                      'modelID': m,
                    };
                    ref
                        .read(preferencesServiceProvider)
                        .saveSessionModel(session.id, p, m);
                  },
                  'selectedModel': ref.read(activeModelProvider),
                },
              );
            },
            tooltip: 'Models',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Builder(
              builder: (context) {
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

                  if (_isBusy) {
                    return const SizedBox.shrink();
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
                          child: Icon(
                            Icons.terminal,
                            size: 32,
                            color: AppTheme.accent,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Start a conversation',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Mode: ${mode.toUpperCase()}',
                          style: TextStyle(
                            color: mode == 'plan'
                                ? AppTheme.info
                                : AppTheme.accent,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  cacheExtent: 800,
                  addAutomaticKeepAlives: false,
                  addRepaintBoundaries: true,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
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
              },
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

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Role header
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 12,
                  color: isUser ? AppTheme.info : AppTheme.accent,
                ),
                const SizedBox(width: 6),
                Text(
                  isUser ? 'YOU' : 'ASSISTANT',
                  style: TextStyle(
                    color: isUser ? AppTheme.info : AppTheme.accent,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                if (!isUser && msg.info is AssistantMessageInfo) ...[
                  const SizedBox(width: 8),
                  Text(
                    (msg.info as AssistantMessageInfo).modelID,
                    style: const TextStyle(
                      color: AppTheme.textTertiary,
                      fontSize: 9,
                    ),
                  ),
                ],
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
              child: Row(
                children: [
                  Text(
                    '\$${(msg.info as AssistantMessageInfo).cost.toStringAsFixed(4)}',
                    style: const TextStyle(
                      color: AppTheme.textTertiary,
                      fontSize: 9,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${(msg.info as AssistantMessageInfo).tokens.input + (msg.info as AssistantMessageInfo).tokens.output} tokens',
                    style: const TextStyle(
                      color: AppTheme.textTertiary,
                      fontSize: 9,
                    ),
                  ),
                  if ((msg.info as AssistantMessageInfo).mode.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      (msg.info as AssistantMessageInfo).mode.toUpperCase(),
                      style: const TextStyle(
                        color: AppTheme.textTertiary,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
