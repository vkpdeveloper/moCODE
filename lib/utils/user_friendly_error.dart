import 'dart:async';

import '../services/codex_rpc_service.dart';

String userFriendlyError(Object error) {
  if (error is TimeoutException) {
    return 'Request timed out. Please check server connection and retry.';
  }

  if (error is CodexRpcException) {
    final msg = error.message.toLowerCase();
    if (msg.contains('no rollout found')) {
      return 'This session history is unavailable on the server. Open another session or create a new one.';
    }
    if (msg.contains('thread not found')) {
      return 'Session is not loaded on server yet. Please retry.';
    }
    if (msg.contains('disconnected')) {
      return 'Disconnected from Codex server. Reconnect from settings.';
    }
    if (error.code == -32600) {
      return 'Server rejected the request. Please retry.';
    }
    return error.message;
  }

  final text = error.toString();
  final lower = text.toLowerCase();
  if (lower.contains('no rollout found')) {
    return 'This session history is unavailable on the server. Open another session or create a new one.';
  }
  if (lower.contains('thread not found')) {
    return 'Session is not loaded on server yet. Please retry.';
  }
  if (lower.contains('disconnected')) {
    return 'Disconnected from Codex server. Reconnect from settings.';
  }
  return text;
}
