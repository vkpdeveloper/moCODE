import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';

class ActiveSessionManager extends ConsumerStatefulWidget {
  final Widget child;

  const ActiveSessionManager({super.key, required this.child});

  @override
  ConsumerState<ActiveSessionManager> createState() =>
      _ActiveSessionManagerState();
}

class _ActiveSessionManagerState extends ConsumerState<ActiveSessionManager> {
  static const Duration _releaseGrace = Duration(seconds: 6);
  final Set<String> _retainedDirectories = {};
  ProviderSubscription<Map<String, String>>? _subscription;
  Timer? _validateTimer;
  Timer? _pollTimer;
  bool _isValidating = false;

  @override
  void initState() {
    super.initState();
    _syncDirectories(ref.read(activeSessionsProvider));
    _subscription = ref.listenManual<Map<String, String>>(
      activeSessionsProvider,
      (prev, next) => _syncDirectories(next),
    );
  }

  @override
  void dispose() {
    _subscription?.close();
    _validateTimer?.cancel();
    _pollTimer?.cancel();
    final eventService = ref.read(eventServiceProvider);
    for (final directory in _retainedDirectories) {
      eventService.release(directory, grace: Duration.zero);
    }
    _retainedDirectories.clear();
    super.dispose();
  }

  void _syncDirectories(Map<String, String> activeSessions) {
    if (!mounted) return;
    final nextDirectories = activeSessions.values.toSet();
    final eventService = ref.read(eventServiceProvider);

    for (final directory in nextDirectories) {
      if (_retainedDirectories.contains(directory)) continue;
      eventService.retain(directory);
    }

    for (final directory in _retainedDirectories) {
      if (nextDirectories.contains(directory)) continue;
      eventService.release(directory, grace: _releaseGrace);
    }

    _retainedDirectories
      ..clear()
      ..addAll(nextDirectories);

    _startOrStopPolling(activeSessions);
  }

  void _startOrStopPolling(Map<String, String> activeSessions) {
    if (activeSessions.isEmpty) {
      _pollTimer?.cancel();
      _pollTimer = null;
      return;
    }
    if (_pollTimer != null) return;
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      _validateActiveSessions(ref.read(activeSessionsProvider));
    });
    _validateActiveSessions(activeSessions);
  }

  void _scheduleValidation(Map<String, String> activeSessions) {
    _validateTimer?.cancel();
    _validateTimer = Timer(const Duration(milliseconds: 250), () {
      _validateActiveSessions(activeSessions);
    });
  }

  Future<void> _validateActiveSessions(
    Map<String, String> activeSessions,
  ) async {
    if (_isValidating) return;
    _isValidating = true;
    try {
      if (activeSessions.isEmpty) return;
      final sessionService = ref.read(sessionServiceProvider);
      final grouped = <String, List<String>>{};
      activeSessions.forEach((sessionId, directory) {
        grouped.putIfAbsent(directory, () => []).add(sessionId);
      });

      for (final entry in grouped.entries) {
        final directory = entry.key;
        final sessionIds = entry.value;
        try {
          final status = await sessionService.getSessionStatus(
            directory: directory,
          );
          for (final sessionId in sessionIds) {
            final info = status[sessionId];
            if (info == null || _isIdleStatus(info)) {
              await ref
                  .read(activeSessionsProvider.notifier)
                  .clearActive(sessionId);
            }
          }
        } catch (_) {
          // ignore validation errors
        }
      }
    } finally {
      _isValidating = false;
    }
  }

  bool _isIdleStatus(dynamic info) {
    if (info == null) return true;
    if (info is String) return info == 'idle';
    if (info is Map<String, dynamic>) {
      return info['type']?.toString() == 'idle';
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
