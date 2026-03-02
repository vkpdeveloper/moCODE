import 'dart:async';
import 'dart:convert';

import '../models/message.dart';
import '../models/part.dart';
import '../models/project.dart';
import '../models/provider.dart';
import '../models/session.dart';
import 'codex_rpc_service.dart';
import '../utils/app_logger.dart';

class CodexAppServerService {
  CodexAppServerService(this._rpc);

  final CodexRpcService _rpc;
  static const String _tag = 'codex.app';

  final Map<String, _CodexMessageState> _messageState = {};
  final Map<String, String> _deltaBuffers = <String, String>{};
  final Map<String, _PendingServerRequest> _pendingRequests = {};
  final Set<String> _resumedThreads = <String>{};
  final Map<String, Map<String, String>> _threadModels =
      <String, Map<String, String>>{};
  final Map<String, String> _latestUserMessageByThread = <String, String>{};
  final Map<String, String> _turnParentByThread = <String, String>{};
  final Map<String, String> _assistantMessageByTurn = <String, String>{};
  final Map<String, String> _threadPaths = <String, String>{};
  final Map<String, String> _threadCwds = <String, String>{};
  final Map<String, Map<String, dynamic>> _threadTurnDefaults =
      <String, Map<String, dynamic>>{};
  final Set<String> _locallyCreatedThreads = <String>{};
  bool _authRecoveryInFlight = false;
  DateTime? _lastAuthRecoveryAt;

  Future<List<Session>> listSessions({String? workspace}) async {
    AppLogger.info(_tag, 'listSessions:start', data: {'workspace': workspace});
    try {
      final normalizedWorkspace = workspace?.trim();
      final result = await _rpc.call('thread/list', {
        'limit': 200,
        'archived': false,
      });

      final data = (result['data'] as List?) ?? const [];
      final sessions = data
          .whereType<Map>()
          .map((raw) {
            final thread = Map<String, dynamic>.from(raw);
            _cacheThreadMetadataFromThread(thread);
            return _toSession(thread, workspace);
          })
          .where((session) {
            if (normalizedWorkspace == null || normalizedWorkspace.isEmpty) {
              return true;
            }
            return session.directory == normalizedWorkspace;
          })
          .toList();
      AppLogger.info(
        _tag,
        'listSessions:done',
        data: {'count': sessions.length},
      );
      return sessions;
    } catch (error) {
      AppLogger.error(
        _tag,
        'listSessions:error',
        data: {'workspace': workspace, 'error': error.toString()},
      );
      rethrow;
    }
  }

  Future<Session> createSession({
    String? workspace,
    String? model,
    String? modelProvider,
  }) async {
    AppLogger.info(
      _tag,
      'createSession:start',
      data: {'workspace': workspace, 'model': model, 'provider': modelProvider},
    );
    try {
      final result = await _rpc.call('thread/start', {
        if (workspace != null && workspace.trim().isNotEmpty) 'cwd': workspace,
        if (model != null && model.isNotEmpty) 'model': model,
        if (modelProvider != null && modelProvider.isNotEmpty)
          'modelProvider': modelProvider,
        'experimentalRawEvents': false,
        'persistExtendedHistory': true,
      });

      final threadRaw = result['thread'];
      if (threadRaw is! Map) {
        throw StateError('Invalid thread/start response');
      }
      final thread = Map<String, dynamic>.from(threadRaw);
      _cacheThreadMetadataFromThread(thread);
      final session = _toSession(thread, workspace);
      _cacheThreadModel(result, session.id);
      _locallyCreatedThreads.add(session.id);
      _resumedThreads.add(session.id);
      AppLogger.info(
        _tag,
        'createSession:done',
        data: {'sessionId': session.id},
      );
      return session;
    } catch (error) {
      AppLogger.error(
        _tag,
        'createSession:error',
        data: {'workspace': workspace, 'error': error.toString()},
      );
      rethrow;
    }
  }

  Future<Session> getSession(String threadId, {String? workspace}) async {
    AppLogger.debug(
      _tag,
      'getSession:start',
      data: {'threadId': threadId, 'workspace': workspace},
    );
    await _resumeThread(threadId, workspace: workspace);
    final result = await _rpc.call('thread/read', {
      'threadId': threadId,
      'includeTurns': false,
    });
    final threadRaw = result['thread'];
    if (threadRaw is! Map) {
      throw StateError('Invalid thread/read response');
    }
    final thread = Map<String, dynamic>.from(threadRaw);
    _cacheThreadMetadataFromThread(thread);
    final session = _toSession(thread, workspace);
    AppLogger.debug(_tag, 'getSession:done', data: {'sessionId': session.id});
    return session;
  }

  Future<void> archiveThread(String threadId) async {
    AppLogger.info(_tag, 'archiveThread', data: {'threadId': threadId});
    await _rpc.call('thread/archive', {'threadId': threadId});
  }

  Future<void> unarchiveThread(String threadId) async {
    AppLogger.info(_tag, 'unarchiveThread', data: {'threadId': threadId});
    await _rpc.call('thread/unarchive', {'threadId': threadId});
  }

  Future<void> setThreadName(String threadId, String name) async {
    AppLogger.info(
      _tag,
      'setThreadName',
      data: {'threadId': threadId, 'name': name},
    );
    await _rpc.call('thread/name/set', {'threadId': threadId, 'name': name});
  }

  Future<Session> forkThread(String threadId, {String? workspace}) async {
    AppLogger.info(
      _tag,
      'forkThread:start',
      data: {'threadId': threadId, 'workspace': workspace},
    );
    final result = await _rpc.call('thread/fork', {'threadId': threadId});
    final threadRaw = result['thread'];
    if (threadRaw is! Map) {
      throw StateError('Invalid thread/fork response');
    }
    final thread = Map<String, dynamic>.from(threadRaw);
    _cacheThreadMetadataFromThread(thread);
    final session = _toSession(thread, workspace);
    AppLogger.info(
      _tag,
      'forkThread:done',
      data: {'sourceThreadId': threadId, 'sessionId': session.id},
    );
    return session;
  }

  Future<void> rollbackThread(String threadId) async {
    AppLogger.info(_tag, 'rollbackThread', data: {'threadId': threadId});
    await _rpc.call('thread/rollback', {'threadId': threadId});
  }

  Future<void> interruptTurn(String threadId) async {
    AppLogger.info(_tag, 'interruptTurn', data: {'threadId': threadId});
    await _rpc.call('turn/interrupt', {'threadId': threadId});
  }

  Future<List<MessageWrapper>> getMessages(
    String threadId, {
    String? workspace,
  }) async {
    AppLogger.debug(
      'codex.app',
      'getMessages:start',
      data: {'threadId': threadId},
    );
    await _resumeThread(threadId, workspace: workspace);
    final result = await _rpc.call('thread/read', {
      'threadId': threadId,
      'includeTurns': true,
    });
    final threadRaw = result['thread'];
    if (threadRaw is! Map) return const [];
    final thread = Map<String, dynamic>.from(threadRaw);
    _cacheThreadMetadataFromThread(thread);
    final resolvedWorkspace =
        thread['cwd']?.toString() ??
        (workspace == null || workspace.trim().isEmpty ? '/' : workspace);
    final turns = (thread['turns'] as List?) ?? const [];

    final wrappers = <MessageWrapper>[];
    for (final turnRaw in turns.whereType<Map>()) {
      final turn = Map<String, dynamic>.from(turnRaw);
      final turnId = turn['id']?.toString();
      final assistantMessageId = _assistantMessageIdForTurn(threadId, turnId);
      final items = (turn['items'] as List?) ?? const [];
      String? turnUserMessageId;
      for (final itemRaw in items.whereType<Map>()) {
        final item = Map<String, dynamic>.from(itemRaw);
        final mapped = _wrappersFromThreadItem(
          threadId: threadId,
          workspace: resolvedWorkspace,
          item: item,
          parentUserMessageId: turnUserMessageId,
          assistantMessageIdOverride: assistantMessageId,
        );
        if (mapped.isNotEmpty) {
          wrappers.addAll(mapped);
        }
        if (item['type']?.toString() == 'userMessage' && mapped.isNotEmpty) {
          turnUserMessageId = mapped.first.info.id;
        }
      }
      if (turnUserMessageId != null && turnUserMessageId.isNotEmpty) {
        _latestUserMessageByThread[threadId] = turnUserMessageId;
      }
    }
    final merged = _mergeWrappersByMessageId(wrappers);

    AppLogger.debug(
      'codex.app',
      'getMessages:done',
      data: {'threadId': threadId, 'count': merged.length},
    );
    return merged;
  }

  Future<void> startTurn({
    required String threadId,
    required String text,
    String? workspace,
    String? model,
  }) async {
    AppLogger.info(
      _tag,
      'startTurn',
      data: {'threadId': threadId, 'workspace': workspace, 'model': model},
    );
    try {
      await _resumeThread(threadId, workspace: workspace);
      await _startTurnRequest(
        threadId: threadId,
        text: text,
        workspace: workspace,
        model: model,
      );
      AppLogger.info(_tag, 'startTurn:accepted', data: {'threadId': threadId});
    } on CodexRpcException catch (error) {
      if (error.contains('thread not found')) {
        AppLogger.warn(
          _tag,
          'startTurn:threadNotLoadedRetry',
          data: {'threadId': threadId},
        );
        await _forceResumeThread(threadId, workspace: workspace);
        await _startTurnRequest(
          threadId: threadId,
          text: text,
          workspace: workspace,
          model: model,
        );
        AppLogger.info(
          _tag,
          'startTurn:acceptedAfterResume',
          data: {'threadId': threadId},
        );
        return;
      }
      if (error.contains('no rollout found')) {
        await _retryStartTurnAfterRolloutMiss(
          threadId: threadId,
          text: text,
          workspace: workspace,
          model: model,
          cause: error.message,
        );
        return;
      }
      AppLogger.error(
        _tag,
        'startTurn:error',
        data: {'threadId': threadId, 'error': error.toString()},
      );
      rethrow;
    } catch (error) {
      AppLogger.error(
        _tag,
        'startTurn:error',
        data: {'threadId': threadId, 'error': error.toString()},
      );
      rethrow;
    }
  }

  Future<void> _retryStartTurnAfterRolloutMiss({
    required String threadId,
    required String text,
    String? workspace,
    String? model,
    required String cause,
  }) async {
    const backoff = <Duration>[
      Duration(milliseconds: 150),
      Duration(milliseconds: 350),
      Duration(milliseconds: 700),
    ];
    for (var i = 0; i < backoff.length; i++) {
      final attempt = i + 1;
      AppLogger.warn(
        _tag,
        'startTurn:noRolloutRetry',
        data: {'threadId': threadId, 'attempt': attempt, 'cause': cause},
      );
      await _forceResumeThread(threadId, workspace: workspace);
      await Future<void>.delayed(backoff[i]);
      try {
        await _startTurnRequest(
          threadId: threadId,
          text: text,
          workspace: workspace,
          model: model,
        );
        AppLogger.info(
          _tag,
          'startTurn:acceptedAfterNoRolloutRetry',
          data: {'threadId': threadId, 'attempt': attempt},
        );
        return;
      } on CodexRpcException catch (error) {
        final exhausted = attempt == backoff.length;
        if (!error.contains('no rollout found') &&
            !error.contains('thread not found')) {
          rethrow;
        }
        if (exhausted) rethrow;
      }
    }
  }

  Future<void> _startTurnRequest({
    required String threadId,
    required String text,
    String? workspace,
    String? model,
  }) async {
    final base = <String, dynamic>{
      'threadId': threadId,
      if ((workspace != null && workspace.trim().isNotEmpty) ||
          (_threadCwds[threadId] != null && _threadCwds[threadId]!.isNotEmpty))
        'cwd': (workspace != null && workspace.trim().isNotEmpty)
            ? workspace
            : _threadCwds[threadId],
      if (model != null && model.isNotEmpty) 'model': model,
    };
    final defaults = _threadTurnDefaults[threadId];
    if (defaults != null) {
      if (defaults.containsKey('approvalPolicy')) {
        base['approvalPolicy'] = defaults['approvalPolicy'];
      }
      if (defaults.containsKey('sandboxPolicy')) {
        base['sandboxPolicy'] = defaults['sandboxPolicy'];
      }
    }
    final inputPayload = <String, dynamic>{
      ...base,
      'input': [
        {
          'type': 'text',
          'text': text,
          'text_elements': <Map<String, dynamic>>[],
        },
      ],
    };
    try {
      await _rpc.call('turn/start', inputPayload);
      return;
    } on CodexRpcException catch (error) {
      final message = error.message.toLowerCase();
      final shouldRetryWithItems =
          message.contains('missing field `items`') ||
          message.contains('unknown field `input`') ||
          message.contains('invalid params');
      if (!shouldRetryWithItems) rethrow;
      final itemsPayload = <String, dynamic>{
        ...base,
        'items': [
          {
            'type': 'text',
            'data': {'text': text},
          },
        ],
      };
      AppLogger.warn(
        _tag,
        'startTurn:retryWithItems',
        data: {'threadId': threadId, 'error': error.message},
      );
      await _rpc.call('turn/start', itemsPayload);
    }
  }

  Future<Map<String, String>?> resolveSessionModel(
    String threadId, {
    String? workspace,
  }) async {
    final cached = _threadModels[threadId];
    if (cached != null) {
      return Map<String, String>.from(cached);
    }
    await _forceResumeThread(threadId, workspace: workspace);
    final updated = _threadModels[threadId];
    if (updated == null) return null;
    return Map<String, String>.from(updated);
  }

  Future<void> _resumeThread(String threadId, {String? workspace}) async {
    if (_resumedThreads.contains(threadId)) return;
    await _forceResumeThread(threadId, workspace: workspace);
  }

  Future<void> _forceResumeThread(String threadId, {String? workspace}) async {
    final resolvedWorkspace = (workspace != null && workspace.trim().isNotEmpty)
        ? workspace
        : _threadCwds[threadId];
    AppLogger.info(
      _tag,
      'threadResume:start',
      data: {
        'threadId': threadId,
        'workspace': resolvedWorkspace,
        'workspaceProvided': workspace != null && workspace.trim().isNotEmpty,
      },
    );
    try {
      final result = await _rpc.call('thread/resume', {
        'threadId': threadId,
        if (resolvedWorkspace != null && resolvedWorkspace.trim().isNotEmpty)
          'cwd': resolvedWorkspace,
        'persistExtendedHistory': true,
      });
      _cacheThreadModel(result, threadId);
      final threadRaw = result['thread'];
      if (threadRaw is Map) {
        _cacheThreadMetadataFromThread(Map<String, dynamic>.from(threadRaw));
      }
      _resumedThreads.add(threadId);
      _locallyCreatedThreads.remove(threadId);
      AppLogger.info(_tag, 'threadResume:done', data: {'threadId': threadId});
    } on CodexRpcException catch (error) {
      final path = _threadPaths[threadId];
      if (error.contains('no rollout found') &&
          path != null &&
          path.isNotEmpty) {
        AppLogger.warn(
          _tag,
          'threadResume:retryWithPath',
          data: {'threadId': threadId, 'path': path},
        );
        final result = await _rpc.call('thread/resume', {
          'threadId': threadId,
          'path': path,
          if (resolvedWorkspace != null && resolvedWorkspace.trim().isNotEmpty)
            'cwd': resolvedWorkspace,
          'persistExtendedHistory': true,
        });
        _cacheThreadModel(result, threadId);
        final threadRaw = result['thread'];
        if (threadRaw is Map) {
          _cacheThreadMetadataFromThread(Map<String, dynamic>.from(threadRaw));
        }
        _resumedThreads.add(threadId);
        _locallyCreatedThreads.remove(threadId);
        AppLogger.info(
          _tag,
          'threadResume:doneWithPath',
          data: {'threadId': threadId},
        );
        return;
      }
      if (error.contains('no rollout found') &&
          _locallyCreatedThreads.contains(threadId)) {
        AppLogger.warn(
          _tag,
          'threadResume:noRolloutForFreshThread',
          data: {'threadId': threadId, 'message': error.message},
        );
        // Freshly created threads are already active on this connection; avoid
        // forcing a failing resume before the first turn starts.
        _resumedThreads.add(threadId);
        return;
      }
      // Some sessions may not have rollout persisted. We continue without
      // failing hard so list/chat can still operate when possible.
      if (error.contains('no rollout found')) {
        AppLogger.warn(
          _tag,
          'threadResume:noRollout',
          data: {'threadId': threadId, 'message': error.message},
        );
        return;
      }
      rethrow;
    }
  }

  void _cacheThreadModel(Map<String, dynamic> response, String threadId) {
    final providerRaw = response['modelProvider']?.toString();
    final modelRaw = response['model']?.toString();
    if (modelRaw == null || modelRaw.isEmpty) return;

    var provider = (providerRaw == null || providerRaw.isEmpty)
        ? 'codex'
        : providerRaw;
    var model = modelRaw;

    if (model.contains('/')) {
      final split = model.split('/');
      if (split.length > 1) {
        if (providerRaw == null || providerRaw.isEmpty) {
          provider = split.first;
        }
        if (split.first == provider) {
          model = split.sublist(1).join('/');
        }
      }
    }

    _threadModels[threadId] = <String, String>{
      'providerID': provider,
      'modelID': model,
    };

    final defaults = <String, dynamic>{};
    if (response.containsKey('approvalPolicy')) {
      defaults['approvalPolicy'] = response['approvalPolicy'];
    }
    final sandbox = response['sandboxPolicy'] ?? response['sandbox'];
    if (sandbox != null) {
      defaults['sandboxPolicy'] = sandbox;
    }
    if (defaults.isNotEmpty) {
      _threadTurnDefaults[threadId] = defaults;
    }

    final cwdRaw = response['cwd']?.toString();
    if (cwdRaw != null && cwdRaw.isNotEmpty) {
      _threadCwds[threadId] = cwdRaw;
    }
  }

  void _cacheThreadMetadataFromThread(Map<String, dynamic> thread) {
    final id = thread['id']?.toString();
    if (id == null || id.isEmpty) return;
    final path = thread['path']?.toString();
    if (path != null && path.isNotEmpty && path != 'null') {
      _threadPaths[id] = path;
    }
    final cwd = thread['cwd']?.toString();
    if (cwd != null && cwd.isNotEmpty) {
      _threadCwds[id] = cwd;
    }
  }

  Future<ProviderListResponse> listModels() async {
    AppLogger.info(_tag, 'listModels:start');
    try {
      final result = await _rpc.call('model/list', {'limit': 300});
      final data = (result['data'] as List?) ?? const [];
      final grouped = <String, List<ProviderModelInfo>>{};

      for (final raw in data.whereType<Map>()) {
        final model = Map<String, dynamic>.from(raw);
        final modelPath = model['model']?.toString() ?? model['id']?.toString();
        if (modelPath == null || modelPath.isEmpty) continue;

        final parts = modelPath.split('/');
        final providerId = parts.length > 1 ? parts.first : 'codex';
        final modelId = parts.length > 1
            ? parts.sublist(1).join('/')
            : modelPath;

        final info = ProviderModelInfo(
          id: modelId,
          name: model['displayName']?.toString() ?? modelId,
          status: model['hidden'] == true ? 'hidden' : 'stable',
        );
        grouped.putIfAbsent(providerId, () => []).add(info);
      }

      final providers = grouped.entries
          .map(
            (entry) => ProviderModel(
              id: entry.key,
              name: entry.key,
              models: entry.value,
            ),
          )
          .toList();

      final response = ProviderListResponse(
        providers: providers,
        connected: grouped.keys.toList(),
      );
      AppLogger.info(
        _tag,
        'listModels:done',
        data: {
          'providers': response.providers.length,
          'connected': response.connected.length,
        },
      );
      return response;
    } catch (error) {
      AppLogger.error(
        _tag,
        'listModels:error',
        data: {'error': error.toString()},
      );
      rethrow;
    }
  }

  Stream<Map<String, dynamic>> subscribeEvents({String? workspace}) {
    final resolvedWorkspace = workspace == null || workspace.trim().isEmpty
        ? '/'
        : workspace;
    AppLogger.info(
      _tag,
      'subscribeEvents:start',
      data: {'workspace': workspace},
    );
    final controller = StreamController<Map<String, dynamic>>();
    StreamSubscription? notifSub;
    StreamSubscription? reqSub;

    Future<void> start() async {
      try {
        await _rpc.ensureConnected();
      } catch (error) {
        AppLogger.error(
          _tag,
          'subscribeEvents:connectFailed',
          data: {'workspace': workspace, 'error': error.toString()},
        );
        if (!controller.isClosed) {
          controller.addError(error);
        }
        return;
      }
      if (!controller.isClosed) {
        controller.add({'type': '__reconnected__'});
      }

      notifSub = _rpc.notifications.listen((notif) {
        final method = notif['method']?.toString();
        if (method == null) return;
        final paramsRaw = notif['params'];
        final params = paramsRaw is Map<String, dynamic>
            ? paramsRaw
            : paramsRaw is Map
            ? Map<String, dynamic>.from(paramsRaw)
            : <String, dynamic>{};
        final mapped = _mapNotification(method, params, resolvedWorkspace);
        if (mapped != null && !controller.isClosed) {
          AppLogger.debug(
            'codex.app',
            'event:mappedNotification',
            data: {'method': method, 'type': mapped['type']},
          );
          controller.add(mapped);
        } else {
          AppLogger.debug(
            _tag,
            'event:ignoredNotification',
            data: {'method': method},
          );
        }
      }, onError: controller.addError);

      reqSub = _rpc.serverRequests.listen((request) {
        final mapped = _mapServerRequest(request);
        if (mapped != null && !controller.isClosed) {
          AppLogger.debug(
            'codex.app',
            'event:mappedServerRequest',
            data: {'type': mapped['type']},
          );
          controller.add(mapped);
        } else {
          AppLogger.debug(
            _tag,
            'event:ignoredServerRequest',
            data: {'method': request['method']?.toString() ?? 'unknown'},
          );
        }
      }, onError: controller.addError);
    }

    unawaited(start());

    controller.onCancel = () async {
      AppLogger.info(_tag, 'subscribeEvents:cancel');
      await notifSub?.cancel();
      await reqSub?.cancel();
    };

    return controller.stream;
  }

  Future<void> respondPermission(String requestId, String reply) async {
    AppLogger.info(
      'codex.app',
      'respondPermission',
      data: {'requestId': requestId, 'reply': reply},
    );
    final pending = _pendingRequests[requestId];
    if (pending == null) {
      AppLogger.warn(
        _tag,
        'respondPermission:missingRequest',
        data: {'requestId': requestId},
      );
      return;
    }
    if (pending.method != 'item/commandExecution/requestApproval' &&
        pending.method != 'item/fileChange/requestApproval') {
      return;
    }

    final decision = switch (reply) {
      'always' => 'acceptForSession',
      'once' => 'accept',
      _ => 'decline',
    };

    await _rpc.respond(pending.rpcId, {'decision': decision});
    _pendingRequests.remove(requestId);
    AppLogger.info(
      _tag,
      'respondPermission:done',
      data: {'requestId': requestId, 'decision': decision},
    );
  }

  Future<void> respondQuestion(
    String requestId,
    List<List<String>> answers, {
    bool rejected = false,
  }) async {
    AppLogger.info(
      'codex.app',
      'respondQuestion',
      data: {'requestId': requestId, 'rejected': rejected},
    );
    final pending = _pendingRequests[requestId];
    if (pending == null) {
      AppLogger.warn(
        _tag,
        'respondQuestion:missingRequest',
        data: {'requestId': requestId},
      );
      return;
    }
    if (pending.method != 'item/tool/requestUserInput') {
      AppLogger.warn(
        _tag,
        'respondQuestion:unexpectedMethod',
        data: {'requestId': requestId, 'method': pending.method},
      );
      return;
    }

    final params = pending.params;
    final questions = (params['questions'] as List?) ?? const [];
    final answerMap = <String, dynamic>{};

    if (!rejected) {
      for (var i = 0; i < questions.length && i < answers.length; i++) {
        final raw = questions[i];
        if (raw is! Map) continue;
        final q = Map<String, dynamic>.from(raw);
        final qid = q['id']?.toString();
        if (qid == null || qid.isEmpty) continue;
        answerMap[qid] = {'answers': answers[i]};
      }
    }

    await _rpc.respond(pending.rpcId, {'answers': answerMap});
    _pendingRequests.remove(requestId);
    AppLogger.info(
      _tag,
      'respondQuestion:done',
      data: {'requestId': requestId, 'answerCount': answerMap.length},
    );
  }

  Future<String?> recoverAuthSilently() async {
    if (_authRecoveryInFlight) return null;
    final now = DateTime.now();
    if (_lastAuthRecoveryAt != null &&
        now.difference(_lastAuthRecoveryAt!) < const Duration(seconds: 20)) {
      return null;
    }
    _authRecoveryInFlight = true;
    _lastAuthRecoveryAt = now;
    try {
      AppLogger.info(_tag, 'auth.recover:start');
      final account = await _rpc.call('account/read', {'refreshToken': true});
      final needsAuth = account['requiresOpenaiAuth'] == true;
      if (!needsAuth) {
        AppLogger.info(_tag, 'auth.recover:alreadyAuthenticated');
        return null;
      }
      final login = await _rpc.call('account/login/start', {'type': 'chatgpt'});
      final authUrl = login['authUrl']?.toString();
      AppLogger.info(
        _tag,
        'auth.recover:loginStarted',
        data: {'hasAuthUrl': authUrl != null && authUrl.isNotEmpty},
      );
      if (authUrl == null || authUrl.isEmpty) return null;
      return authUrl;
    } catch (error) {
      AppLogger.error(
        _tag,
        'auth.recover:error',
        data: {'error': error.toString()},
      );
      return null;
    } finally {
      _authRecoveryInFlight = false;
    }
  }

  Map<String, dynamic>? _mapNotification(
    String method,
    Map<String, dynamic> params,
    String workspace,
  ) {
    if (method == 'error' || method == 'codex/event/error') {
      final threadId = _firstString(params, const ['threadId', 'thread_id']);
      final errorRaw = params['error'];
      final errorMap = errorRaw is Map
          ? Map<String, dynamic>.from(errorRaw)
          : <String, dynamic>{};
      final message = errorMap['message']?.toString();
      final details = errorMap['additionalDetails']?.toString();
      final codexErrorInfo = errorMap['codexErrorInfo'];
      final mergedMessage = [
        if (message != null && message.isNotEmpty) message,
        if (details != null && details.isNotEmpty) details,
      ].join('\n');
      final friendlyMessage = _normalizeServerErrorMessage(mergedMessage);
      if (method == 'codex/event/error' &&
          (threadId == null || threadId.isEmpty) &&
          friendlyMessage.isEmpty) {
        AppLogger.debug(
          _tag,
          'notification:skipTransientCodexError',
          data: {'method': method},
        );
        return null;
      }
      AppLogger.error(
        _tag,
        'notification:turnError',
        data: {
          'method': method,
          'threadId': threadId,
          'message': friendlyMessage,
          'willRetry': params['willRetry'],
          'turnId': params['turnId'],
          'codexErrorInfo': codexErrorInfo,
        },
      );

      return {
        'type': 'session.error',
        'properties': {
          if (threadId != null && threadId.isNotEmpty) 'sessionID': threadId,
          'error': {
            'name': 'codex.turn.error',
            'data': {
              'message': mergedMessage.isEmpty
                  ? 'Codex failed to complete this turn.'
                  : friendlyMessage,
              'codexErrorInfo': codexErrorInfo,
              'willRetry': params['willRetry'],
              'turnId': params['turnId'],
              'source': method,
            },
          },
        },
      };
    }

    if (method == 'codex/event/task_complete') {
      final threadId = _firstString(params, const [
        'threadId',
        'thread_id',
        'conversationId',
        'conversation_id',
      ]);
      return {
        'type': 'session.turn.updated',
        'properties': {
          if (threadId != null && threadId.isNotEmpty) 'sessionID': threadId,
          'source': 'codex/event/task_complete',
        },
      };
    }

    if (method == 'thread/status/changed') {
      final threadId = _firstString(params, const ['threadId', 'thread_id']);
      if (threadId == null) return null;
      final status = params['status'];
      final statusType = status is Map ? status['type']?.toString() : null;
      if (statusType == 'idle') {
        _turnParentByThread.remove(threadId);
        return {
          'type': 'session.idle',
          'properties': {'sessionID': threadId},
        };
      }
      String? message;
      if (status is Map) {
        final activeFlags = status['activeFlags'];
        if (activeFlags is List && activeFlags.isNotEmpty) {
          message = activeFlags.map((e) => e.toString()).join(', ');
        }
      }
      return {
        'type': 'session.status',
        'properties': {
          'sessionID': threadId,
          'status': {
            'type': statusType ?? 'active',
            if (message != null && message.isNotEmpty) 'message': message,
          },
        },
      };
    }

    if (method == 'thread/started') {
      final thread = params['thread'];
      if (thread is! Map) return null;
      final typedThread = Map<String, dynamic>.from(thread);
      _cacheThreadMetadataFromThread(typedThread);
      final session = _toSession(typedThread, workspace);
      _resumedThreads.add(session.id);
      return {
        'type': 'session.created',
        'properties': {'info': session.toJson()},
      };
    }

    if (method == 'item/agentMessage/delta') {
      final threadId = _firstString(params, const ['threadId', 'thread_id']);
      final turnId = _firstString(params, const ['turnId', 'turn_id']);
      final itemId = _firstString(params, const ['itemId', 'item_id']);
      final delta = params['delta']?.toString() ?? '';
      if (threadId == null || itemId == null) return null;
      final assistantMessageId = _assistantMessageIdForTurn(
        threadId,
        turnId,
        fallbackItemId: itemId,
      );

      final state = _messageState.putIfAbsent(
        '$threadId:$itemId',
        () => _CodexMessageState(
          messageId: assistantMessageId,
          partId: '${itemId}_text',
          sessionId: threadId,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      final bufferKey = '$threadId:${state.partId}';
      final fullText = _appendDelta(bufferKey, delta);

      final part = _textPart(
        partId: state.partId,
        messageId: state.messageId,
        sessionId: threadId,
        text: fullText,
      );

      return {
        'type': 'message.part.updated',
        'properties': {'part': part.toJson(), 'delta': delta},
      };
    }

    if (method == 'item/reasoning/summaryTextDelta' ||
        method == 'item/reasoning/textDelta' ||
        method == 'item/plan/delta') {
      final threadId = _firstString(params, const ['threadId', 'thread_id']);
      final turnId = _firstString(params, const ['turnId', 'turn_id']);
      final itemId = _firstString(params, const ['itemId', 'item_id']);
      final delta = params['delta']?.toString() ?? '';
      if (threadId == null || itemId == null) return null;
      final assistantMessageId = _assistantMessageIdForTurn(
        threadId,
        turnId,
        fallbackItemId: itemId,
      );
      final partId = '${itemId}_reasoning';
      final fullText = _appendDelta('$threadId:$partId', delta);
      final part = ReasoningPart(
        id: partId,
        sessionID: threadId,
        messageID: assistantMessageId,
        text: fullText,
        metadata: {'source': method},
      );
      return {
        'type': 'message.part.updated',
        'properties': {'part': part.toJson(), 'delta': delta},
      };
    }

    if (method == 'item/commandExecution/outputDelta') {
      final threadId = _firstString(params, const ['threadId', 'thread_id']);
      final turnId = _firstString(params, const ['turnId', 'turn_id']);
      final itemId = _firstString(params, const ['itemId', 'item_id']);
      final delta = params['delta']?.toString() ?? '';
      if (threadId == null || itemId == null) return null;
      final assistantMessageId = _assistantMessageIdForTurn(
        threadId,
        turnId,
        fallbackItemId: itemId,
      );
      final partId = '${itemId}_tool';
      final fullText = _appendDelta('$threadId:$partId', delta);
      final part = ToolPart(
        id: partId,
        sessionID: threadId,
        messageID: assistantMessageId,
        callID: itemId,
        tool: 'shell',
        state: {
          'status': 'running',
          'output': fullText,
          'title': 'Run command',
        },
      );
      return {
        'type': 'message.part.updated',
        'properties': {'part': part.toJson(), 'delta': delta},
      };
    }

    if (method == 'item/fileChange/outputDelta') {
      final threadId = _firstString(params, const ['threadId', 'thread_id']);
      final turnId = _firstString(params, const ['turnId', 'turn_id']);
      final itemId = _firstString(params, const ['itemId', 'item_id']);
      final delta = params['delta']?.toString() ?? '';
      if (threadId == null || itemId == null) return null;
      final assistantMessageId = _assistantMessageIdForTurn(
        threadId,
        turnId,
        fallbackItemId: itemId,
      );
      final partId = '${itemId}_tool';
      final fullText = _appendDelta('$threadId:$partId', delta);
      final part = ToolPart(
        id: partId,
        sessionID: threadId,
        messageID: assistantMessageId,
        callID: itemId,
        tool: 'apply_patch',
        state: {
          'status': 'running',
          'output': fullText,
          'title': 'Apply patch',
        },
      );
      return {
        'type': 'message.part.updated',
        'properties': {'part': part.toJson(), 'delta': delta},
      };
    }

    if (method == 'item/completed') {
      final threadId = _firstString(params, const ['threadId', 'thread_id']);
      final turnId = _firstString(params, const ['turnId', 'turn_id']);
      final itemRaw = params['item'];
      if (threadId == null || itemRaw is! Map) return null;
      final item = Map<String, dynamic>.from(itemRaw);
      final completedItemId = item['id']?.toString();
      if (completedItemId != null && completedItemId.isNotEmpty) {
        _deltaBuffers.remove('$threadId:${completedItemId}_text');
        _deltaBuffers.remove('$threadId:${completedItemId}_reasoning');
        _deltaBuffers.remove('$threadId:${completedItemId}_tool');
      }
      final parentUserMessageId =
          (turnId != null ? _turnParentByThread['$threadId:$turnId'] : null) ??
          _latestUserMessageByThread[threadId];
      final assistantMessageId = _assistantMessageIdForTurn(
        threadId,
        turnId,
        fallbackItemId: item['id']?.toString(),
      );
      final wrappers = _wrappersFromThreadItem(
        threadId: threadId,
        workspace: workspace,
        item: item,
        parentUserMessageId: parentUserMessageId,
        assistantMessageIdOverride: assistantMessageId,
      );
      if (wrappers.isEmpty) return null;
      if (item['type']?.toString() == 'userMessage') {
        final userId = wrappers.first.info.id;
        _latestUserMessageByThread[threadId] = userId;
        if (turnId != null && turnId.isNotEmpty) {
          _turnParentByThread['$threadId:$turnId'] = userId;
        }
      }
      if (wrappers.length == 1) {
        final message = wrappers.first;
        return {
          'type': 'message.updated',
          'properties': {
            'info': message.info.toJson(),
            'parts': message.parts.map((part) => part.toJson()).toList(),
          },
        };
      }
      return {
        'type': 'message.updated',
        'properties': {
          'info': wrappers.first.info.toJson(),
          'parts': wrappers
              .expand((w) => w.parts)
              .map((p) => p.toJson())
              .toList(),
        },
      };
    }

    if (method == 'turn/completed') {
      final threadId = _firstString(params, const ['threadId', 'thread_id']);
      if (threadId == null) return null;
      final turnId = _firstString(params, const ['turnId', 'turn_id']);
      if (turnId != null && turnId.isNotEmpty) {
        _turnParentByThread.remove('$threadId:$turnId');
        _assistantMessageByTurn.remove('$threadId:$turnId');
      }
      return {
        'type': 'session.idle',
        'properties': {'sessionID': threadId},
      };
    }

    if (method == 'turn/started') {
      final threadId = _firstString(params, const ['threadId', 'thread_id']);
      if (threadId == null) return null;
      final turnRaw = params['turn'];
      if (turnRaw is Map) {
        final turn = Map<String, dynamic>.from(turnRaw);
        final turnId = turn['id']?.toString();
        if (turnId != null && turnId.isNotEmpty) {
          _assistantMessageIdForTurn(threadId, turnId);
          final parent = _latestUserMessageByThread[threadId];
          if (parent != null && parent.isNotEmpty) {
            _turnParentByThread['$threadId:$turnId'] = parent;
          }
        }
      }
      return {
        'type': 'session.status',
        'properties': {
          'sessionID': threadId,
          'status': {'type': 'active'},
        },
      };
    }

    AppLogger.debug(_tag, 'notification:unmapped', data: {'method': method});
    return null;
  }

  String? _firstString(Map<String, dynamic> params, List<String> keys) {
    for (final key in keys) {
      final value = params[key]?.toString();
      if (value != null && value.isNotEmpty && value != 'null') {
        return value;
      }
    }
    return null;
  }

  String _normalizeServerErrorMessage(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return '';
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        final detail = decoded['detail']?.toString();
        if (detail != null && detail.isNotEmpty) return detail;
        final message = decoded['message']?.toString();
        if (message != null && message.isNotEmpty) return message;
      }
    } catch (_) {
      // keep original
    }
    return text;
  }

  String _appendDelta(String key, String delta) {
    if (delta.isEmpty) {
      return _deltaBuffers[key] ?? '';
    }
    final next = '${_deltaBuffers[key] ?? ''}$delta';
    _deltaBuffers[key] = next;
    return next;
  }

  String _assistantMessageIdForTurn(
    String threadId,
    String? turnId, {
    String? fallbackItemId,
  }) {
    if (turnId == null || turnId.isEmpty) {
      return fallbackItemId ??
          'assistant_${DateTime.now().microsecondsSinceEpoch}';
    }
    final key = '$threadId:$turnId';
    return _assistantMessageByTurn.putIfAbsent(
      key,
      () => 'turn_${turnId}_assistant',
    );
  }

  List<MessageWrapper> _mergeWrappersByMessageId(List<MessageWrapper> source) {
    if (source.isEmpty) return const [];
    final ordered = <String>[];
    final map = <String, MessageWrapper>{};
    for (final wrapper in source) {
      final id = wrapper.info.id;
      if (!map.containsKey(id)) {
        ordered.add(id);
        map[id] = wrapper;
        continue;
      }
      final existing = map[id]!;
      map[id] = MessageWrapper(
        info: existing.info,
        parts: <Part>[...existing.parts, ...wrapper.parts],
      );
    }
    return ordered.map((id) => map[id]!).toList();
  }

  List<MessageWrapper> _wrappersFromThreadItem({
    required String threadId,
    required String workspace,
    required Map<String, dynamic> item,
    String? parentUserMessageId,
    String? assistantMessageIdOverride,
  }) {
    final type = item['type']?.toString() ?? '';
    if (type == 'userMessage') {
      return <MessageWrapper>[_userMessageFromItem(threadId, item)];
    }
    if (type == 'agentMessage') {
      return <MessageWrapper>[
        _assistantMessageFromItem(
          threadId,
          workspace,
          item,
          messageIdOverride: assistantMessageIdOverride,
          parentID: parentUserMessageId,
        ),
      ];
    }
    if (type == 'reasoning') {
      final itemId =
          item['id']?.toString() ??
          'reasoning_${DateTime.now().microsecondsSinceEpoch}';
      final messageId = assistantMessageIdOverride ?? itemId;
      final summary = (item['summary'] as List?) ?? const [];
      final content = (item['content'] as List?) ?? const [];
      final text = [
        ...summary.map((e) => e.toString()).where((e) => e.trim().isNotEmpty),
        ...content.map((e) => e.toString()).where((e) => e.trim().isNotEmpty),
      ].join('\n');
      if (text.trim().isEmpty) return const [];
      return <MessageWrapper>[
        _assistantWrapperWithParts(
          sessionId: threadId,
          workspace: workspace,
          messageId: messageId,
          parentID: parentUserMessageId,
          parts: <Part>[
            ReasoningPart(
              id: '${itemId}_reasoning',
              sessionID: threadId,
              messageID: messageId,
              text: text,
              metadata: {'source': 'codex.reasoning'},
            ),
          ],
        ),
      ];
    }
    if (type == 'plan') {
      final itemId =
          item['id']?.toString() ??
          'plan_${DateTime.now().microsecondsSinceEpoch}';
      final messageId = assistantMessageIdOverride ?? itemId;
      final text = item['text']?.toString() ?? '';
      if (text.trim().isEmpty) return const [];
      return <MessageWrapper>[
        _assistantWrapperWithParts(
          sessionId: threadId,
          workspace: workspace,
          messageId: messageId,
          parentID: parentUserMessageId,
          parts: <Part>[
            ReasoningPart(
              id: '${itemId}_plan',
              sessionID: threadId,
              messageID: messageId,
              text: text,
              metadata: {'source': 'codex.plan'},
            ),
          ],
        ),
      ];
    }
    if (type == 'commandExecution') {
      final itemId =
          item['id']?.toString() ??
          'cmd_${DateTime.now().microsecondsSinceEpoch}';
      final messageId = assistantMessageIdOverride ?? itemId;
      final command = item['command']?.toString() ?? '';
      final cwd = item['cwd']?.toString() ?? workspace;
      final output = item['aggregatedOutput']?.toString();
      final status = _normalizeOperationalStatus(item['status']?.toString());
      final exitCode = (item['exitCode'] as num?)?.toInt();
      return <MessageWrapper>[
        _assistantWrapperWithParts(
          sessionId: threadId,
          workspace: workspace,
          messageId: messageId,
          parentID: parentUserMessageId,
          parts: <Part>[
            CommandOutputPart(
              id: '${itemId}_command',
              sessionID: threadId,
              messageID: messageId,
              command: command,
              cwd: cwd,
              status: status,
              exitCode: exitCode,
              metadata: {
                if (output != null && output.isNotEmpty) 'output': output,
                if (item['durationMs'] != null)
                  'durationMs': item['durationMs'],
              },
            ),
          ],
        ),
      ];
    }
    if (type == 'fileChange') {
      final itemId =
          item['id']?.toString() ??
          'patch_${DateTime.now().microsecondsSinceEpoch}';
      final messageId = assistantMessageIdOverride ?? itemId;
      final changes = (item['changes'] as List?) ?? const [];
      final files = <String>[];
      final diffs = <String>[];
      for (final raw in changes.whereType<Map>()) {
        final change = Map<String, dynamic>.from(raw);
        final path = change['path']?.toString();
        if (path != null && path.isNotEmpty) files.add(path);
        final diff = change['diff']?.toString();
        if (diff != null && diff.isNotEmpty) diffs.add(diff);
      }
      final status = _normalizeOperationalStatus(item['status']?.toString());
      return <MessageWrapper>[
        _assistantWrapperWithParts(
          sessionId: threadId,
          workspace: workspace,
          messageId: messageId,
          parentID: parentUserMessageId,
          parts: <Part>[
            ToolPart(
              id: '${itemId}_tool',
              sessionID: threadId,
              messageID: messageId,
              callID: itemId,
              tool: 'apply_patch',
              state: {
                'status': status,
                'title': 'Apply patch',
                if (diffs.isNotEmpty) 'output': diffs.join('\n\n'),
              },
            ),
            PatchPart(
              id: '${itemId}_patch',
              sessionID: threadId,
              messageID: messageId,
              hash: itemId,
              files: files,
            ),
          ],
        ),
      ];
    }
    if (type == 'mcpToolCall' ||
        type == 'dynamicToolCall' ||
        type == 'collabAgentToolCall') {
      final itemId =
          item['id']?.toString() ??
          'tool_${DateTime.now().microsecondsSinceEpoch}';
      final messageId = assistantMessageIdOverride ?? itemId;
      final toolName = item['tool']?.toString() ?? type;
      final status = _normalizeOperationalStatus(item['status']?.toString());
      return <MessageWrapper>[
        _assistantWrapperWithParts(
          sessionId: threadId,
          workspace: workspace,
          messageId: messageId,
          parentID: parentUserMessageId,
          parts: <Part>[
            ToolPart(
              id: '${itemId}_tool',
              sessionID: threadId,
              messageID: messageId,
              callID: itemId,
              tool: toolName,
              state: {
                'status': status,
                if (item['arguments'] != null) 'input': item['arguments'],
                if (item['result'] != null) 'output': item['result'],
                if (item['error'] != null) 'error': item['error'],
              },
            ),
          ],
        ),
      ];
    }
    if (type == 'webSearch') {
      final itemId =
          item['id']?.toString() ??
          'web_${DateTime.now().microsecondsSinceEpoch}';
      final messageId = assistantMessageIdOverride ?? itemId;
      return <MessageWrapper>[
        _assistantWrapperWithParts(
          sessionId: threadId,
          workspace: workspace,
          messageId: messageId,
          parentID: parentUserMessageId,
          parts: <Part>[
            ToolPart(
              id: '${itemId}_tool',
              sessionID: threadId,
              messageID: messageId,
              callID: itemId,
              tool: 'web_search',
              state: {
                'status': 'completed',
                'input': item['query']?.toString() ?? '',
                if (item['action'] != null) 'output': item['action'],
              },
            ),
          ],
        ),
      ];
    }
    if (type == 'contextCompaction') {
      final itemId =
          item['id']?.toString() ??
          'compact_${DateTime.now().microsecondsSinceEpoch}';
      final messageId = assistantMessageIdOverride ?? itemId;
      return <MessageWrapper>[
        _assistantWrapperWithParts(
          sessionId: threadId,
          workspace: workspace,
          messageId: messageId,
          parentID: parentUserMessageId,
          parts: <Part>[
            CompactionPart(
              id: '${itemId}_compaction',
              sessionID: threadId,
              messageID: messageId,
              auto: true,
            ),
          ],
        ),
      ];
    }
    return const [];
  }

  String _normalizeOperationalStatus(String? status) {
    return switch (status) {
      'inProgress' => 'running',
      'completed' => 'completed',
      'failed' => 'error',
      'declined' => 'error',
      'pending' => 'pending',
      _ => 'pending',
    };
  }

  MessageWrapper _assistantWrapperWithParts({
    required String sessionId,
    required String workspace,
    required String messageId,
    required List<Part> parts,
    String? parentID,
  }) {
    final info = _assistantInfo(
      messageId: messageId,
      sessionId: sessionId,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      workspace: workspace,
      parentID: parentID,
    );
    return MessageWrapper(info: info, parts: parts);
  }

  Map<String, dynamic>? _mapServerRequest(Map<String, dynamic> request) {
    final method = request['method']?.toString();
    final rpcId = request['id'];
    if (method == null || rpcId == null) {
      AppLogger.warn(
        _tag,
        'serverRequest:invalidPayload',
        data: {'hasMethod': method != null, 'hasId': rpcId != null},
      );
      return null;
    }

    final paramsRaw = request['params'];
    final params = paramsRaw is Map<String, dynamic>
        ? paramsRaw
        : paramsRaw is Map
        ? Map<String, dynamic>.from(paramsRaw)
        : <String, dynamic>{};

    final threadId = params['threadId']?.toString();
    if (threadId == null || threadId.isEmpty) {
      AppLogger.debug(
        _tag,
        'serverRequest:missingThreadId',
        data: {'method': method, 'id': rpcId.toString()},
      );
      return null;
    }
    final appRequestId = 'codex_req_${rpcId.toString()}';

    _pendingRequests[appRequestId] = _PendingServerRequest(
      appId: appRequestId,
      rpcId: rpcId,
      method: method,
      params: params,
    );
    AppLogger.info(
      _tag,
      'serverRequest:received',
      data: {'method': method, 'requestId': appRequestId, 'threadId': threadId},
    );

    if (method == 'item/commandExecution/requestApproval' ||
        method == 'item/fileChange/requestApproval') {
      final command = params['command']?.toString();
      final reason = params['reason']?.toString();
      final patterns = <String>[
        if (command != null && command.isNotEmpty) command,
        if (reason != null && reason.isNotEmpty) reason,
      ];
      return {
        'type': 'permission.asked',
        'properties': {
          'id': appRequestId,
          'sessionID': threadId,
          'permission': method.contains('fileChange')
              ? 'file.change'
              : 'command.execute',
          'patterns': patterns,
          'metadata': {'rpcMethod': method},
          'always': const <String>[],
          'tool': {
            'messageID': params['itemId']?.toString() ?? appRequestId,
            'callID': appRequestId,
          },
        },
      };
    }

    if (method == 'item/tool/requestUserInput') {
      final questionsRaw = (params['questions'] as List?) ?? const [];
      final questions = questionsRaw.whereType<Map>().map((raw) {
        final q = Map<String, dynamic>.from(raw);
        final optionsRaw = (q['options'] as List?) ?? const [];
        return {
          'header': q['header']?.toString() ?? 'Input',
          'question': q['question']?.toString() ?? '',
          'multiple': false,
          'custom': q['isOther'] == true,
          'options': optionsRaw.whereType<Map>().map((opt) {
            final entry = Map<String, dynamic>.from(opt);
            return {
              'label': entry['label']?.toString() ?? '',
              'description': entry['description']?.toString() ?? '',
            };
          }).toList(),
        };
      }).toList();
      return {
        'type': 'question.asked',
        'properties': {
          'id': appRequestId,
          'sessionID': threadId,
          'questions': questions,
          'tool': {
            'messageID': params['itemId']?.toString() ?? appRequestId,
            'callID': appRequestId,
          },
        },
      };
    }

    AppLogger.debug(
      _tag,
      'serverRequest:unmapped',
      data: {'method': method, 'requestId': appRequestId},
    );
    return null;
  }

  MessageWrapper _userMessageFromItem(
    String sessionId,
    Map<String, dynamic> item,
  ) {
    final id =
        item['id']?.toString() ??
        'user_${DateTime.now().microsecondsSinceEpoch}';
    final createdAt = DateTime.now().millisecondsSinceEpoch;
    final info = UserMessageInfo(
      id: id,
      sessionID: sessionId,
      time: MessageTime(created: createdAt),
    );

    final content = (item['content'] as List?) ?? const [];
    final texts = <String>[];
    for (final c in content.whereType<Map>()) {
      final entry = Map<String, dynamic>.from(c);
      final type = entry['type']?.toString();
      if (type == 'text' || type == 'input_text') {
        final t =
            entry['text']?.toString() ??
            (entry['data'] is Map
                ? (entry['data'] as Map)['text']?.toString()
                : null);
        if (t != null && t.isNotEmpty) texts.add(t);
      }
    }

    final textPart = TextPart(
      id: '${id}_text',
      sessionID: sessionId,
      messageID: id,
      synthetic: false,
      text: texts.join('\n'),
    );

    return MessageWrapper(info: info, parts: [textPart]);
  }

  MessageWrapper _assistantMessageFromItem(
    String sessionId,
    String workspace,
    Map<String, dynamic> item, {
    String? messageIdOverride,
    String? parentID,
  }) {
    final itemId =
        item['id']?.toString() ??
        'assistant_${DateTime.now().microsecondsSinceEpoch}';
    final id = messageIdOverride ?? itemId;
    final createdAt = DateTime.now().millisecondsSinceEpoch;
    final info = _assistantInfo(
      messageId: id,
      sessionId: sessionId,
      createdAt: createdAt,
      workspace: workspace,
      parentID: parentID,
    );

    final textPart = _textPart(
      partId: '${itemId}_text',
      messageId: id,
      sessionId: sessionId,
      text: _extractAssistantText(item),
    );

    return MessageWrapper(info: info, parts: [textPart]);
  }

  String _extractAssistantText(Map<String, dynamic> item) {
    final direct = item['text']?.toString();
    if (direct != null && direct.isNotEmpty) return direct;

    final content = item['content'];
    if (content is String && content.isNotEmpty) return content;
    if (content is List) {
      final chunks = <String>[];
      for (final raw in content.whereType<Map>()) {
        final entry = Map<String, dynamic>.from(raw);
        final type = entry['type']?.toString();
        if (type == 'text' || type == 'output_text') {
          final t =
              entry['text']?.toString() ??
              (entry['data'] is Map
                  ? (entry['data'] as Map)['text']?.toString()
                  : null);
          if (t != null && t.isNotEmpty) {
            chunks.add(t);
          }
        }
      }
      if (chunks.isNotEmpty) return chunks.join('\n');
    }
    return '';
  }

  AssistantMessageInfo _assistantInfo({
    required String messageId,
    required String sessionId,
    required int createdAt,
    required String workspace,
    String? parentID,
  }) {
    final threadModel = _threadModels[sessionId];
    final providerId = threadModel?['providerID'] ?? 'codex';
    final modelId = threadModel?['modelID'] ?? 'codex';
    return AssistantMessageInfo(
      id: messageId,
      sessionID: sessionId,
      time: MessageTime(created: createdAt),
      parentID: parentID,
      modelID: modelId,
      providerID: providerId,
      mode: 'build',
      path: MessagePath(cwd: workspace, root: workspace),
      cost: 0,
      tokens: MessageTokens(
        input: 0,
        output: 0,
        reasoning: 0,
        cache: MessageCacheTokens(read: 0, write: 0),
      ),
    );
  }

  TextPart _textPart({
    required String partId,
    required String messageId,
    required String sessionId,
    required String text,
  }) {
    return TextPart(
      id: partId,
      sessionID: sessionId,
      messageID: messageId,
      synthetic: false,
      text: text,
    );
  }

  Session _toSession(Map<String, dynamic> thread, String? workspace) {
    final id = thread['id']?.toString() ?? '';
    final created =
        ((thread['createdAt'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch ~/ 1000) *
        1000;
    final updated =
        ((thread['updatedAt'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch ~/ 1000) *
        1000;
    final cwd = thread['cwd']?.toString() ?? workspace ?? '/';
    final preview = thread['preview']?.toString() ?? '';
    final name = thread['name']?.toString();

    return Session(
      id: id,
      slug: id,
      projectID: _projectIdFromWorkspace(cwd),
      directory: cwd,
      title: (name != null && name.isNotEmpty)
          ? name
          : (preview.isNotEmpty ? preview : 'New Session'),
      version: thread['cliVersion']?.toString() ?? 'codex',
      time: SessionTime(created: created, updated: updated),
    );
  }

  Project pseudoProject(String workspace) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final cleaned = workspace.trim();
    final segments = cleaned.split('/').where((e) => e.isNotEmpty).toList();
    final name = cleaned.isEmpty
        ? 'Codex Workspace'
        : (segments.isEmpty ? cleaned : segments.last);
    return Project(
      id: _projectIdFromWorkspace(cleaned),
      worktree: cleaned,
      name: name,
      time: ProjectTime(created: ts, updated: ts, initialized: ts),
    );
  }

  String _projectIdFromWorkspace(String cwd) {
    return 'codex:${cwd.hashCode.abs()}';
  }
}

class _CodexMessageState {
  _CodexMessageState({
    required this.messageId,
    required this.partId,
    required this.sessionId,
    required this.createdAt,
  });

  final String messageId;
  final String partId;
  final String sessionId;
  final int createdAt;
}

class _PendingServerRequest {
  const _PendingServerRequest({
    required this.appId,
    required this.rpcId,
    required this.method,
    required this.params,
  });

  final String appId;
  final dynamic rpcId;
  final String method;
  final Map<String, dynamic> params;
}
