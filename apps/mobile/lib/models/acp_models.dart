import 'message.dart';
import 'permission_request.dart';
import 'project.dart';
import 'session.dart';

class AcpSessionEntry {
  final String id;
  final int seq;
  final String kind;
  final Object? payload;
  final String createdAt;

  const AcpSessionEntry({
    required this.id,
    required this.seq,
    required this.kind,
    required this.payload,
    required this.createdAt,
  });

  factory AcpSessionEntry.fromJson(Map<String, dynamic> json) {
    return AcpSessionEntry(
      id: json['id'] as String? ?? '',
      seq: (json['seq'] as num?)?.toInt() ?? 0,
      kind: json['kind'] as String? ?? '',
      payload: json['payload'],
      createdAt: json['createdAt'] as String? ?? '',
    );
  }
}

class AcpSessionSnapshot {
  final Session session;
  final List<AcpSessionEntry> entries;

  const AcpSessionSnapshot({
    required this.session,
    required this.entries,
  });
}

Project projectFromAcpJson(Map<String, dynamic> json) {
  return Project.fromJson({
    'id': json['id'],
    'worktree': json['rootPath'],
    'name': json['name'] ?? json['displayName'] ?? json['detectedName'],
    'vcs': 'git',
    'time': {
      'created': _isoToMillis(json['createdAt'] as String?),
      'updated': _isoToMillis(json['updatedAt'] as String?),
      'initialized': _isoToMillis(
        (json['lastOpenedAt'] ?? json['updatedAt']) as String?,
      ),
    },
    'sandboxes': const <String>[],
  });
}

Session sessionFromAcpJson(Map<String, dynamic> json) {
  final id = json['id'] as String? ?? '';
  return Session.fromJson({
    'id': id,
    'slug': id.length <= 8 ? id : id.substring(0, 8),
    'projectID': json['projectId'],
    'agentID': json['agentId'],
    'status': json['status'],
    'directory': json['cwd'],
    'title': (json['title'] as String?)?.trim().isNotEmpty == true
        ? json['title']
        : 'New Session',
    'version': 'acp',
    'time': {
      'created': _isoToMillis(json['createdAt'] as String?),
      'updated': _isoToMillis(json['updatedAt'] as String?),
    },
  });
}

List<MessageWrapper> messageWrappersFromAcpSnapshot(
  AcpSessionSnapshot snapshot,
) {
  final messages = <Map<String, dynamic>>[];
  var currentMode = 'build';
  _AssistantBuilder? currentAssistant;
  String? currentParentId;

  for (final entry in snapshot.entries) {
    final payload = _asObject(entry.payload);
    if (payload == null) {
      continue;
    }

    if (entry.kind == 'current_mode_update') {
      final update = _asObject(payload['update']);
      final nextMode = _asString(update?['currentModeId']);
      if (nextMode != null && nextMode.isNotEmpty) {
        currentMode = nextMode;
      }
      continue;
    }

    if (entry.kind == 'session_info_update') {
      continue;
    }

    if (entry.kind == 'user_message') {
      currentAssistant = null;
      currentParentId = entry.id;
      messages.add(
        _createUserMessage(
          snapshot.session,
          entry.id,
          _asString(payload['text']) ?? '',
          entry.createdAt,
          currentMode,
        ),
      );
      continue;
    }

    if (!_assistantEntryKinds.contains(entry.kind)) {
      continue;
    }

    currentAssistant ??= _AssistantBuilder(
      _createAssistantMessage(
        snapshot.session,
        'assistant:${entry.id}',
        entry.createdAt,
        currentMode,
        currentParentId,
      ),
    );

    if (messages.isEmpty || !identical(messages.last, currentAssistant.message)) {
      messages.add(currentAssistant.message);
    }

    final info = _asObject(currentAssistant.message['info'])!;
    info['mode'] = currentMode;
    final time = _asObject(info['time']) ?? <String, dynamic>{};
    time['completed'] = _isoToMillis(entry.createdAt);
    info['time'] = time;

    if (entry.kind == 'agent_message_chunk') {
      _appendOrMergeTextPart(
        currentAssistant,
        'text',
        _extractTextContent(payload['content']),
        entry.createdAt,
      );
      continue;
    }

    if (entry.kind == 'agent_thought_chunk') {
      _appendOrMergeTextPart(
        currentAssistant,
        'reasoning',
        _extractTextContent(payload['content']),
        entry.createdAt,
      );
      continue;
    }

    if (entry.kind == 'tool_call' || entry.kind == 'tool_call_update') {
      final update = _asObject(payload['update']) ?? payload;
      final toolCallId = _asString(update['toolCallId']);
      if (toolCallId == null || toolCallId.isEmpty) {
        continue;
      }
      _upsertToolPart(currentAssistant, entry.id, toolCallId, update);
      continue;
    }

    if (entry.kind == 'plan') {
      final update = _asObject(payload['update']) ?? payload;
      _upsertPlanPart(currentAssistant, update);
    }
  }

  return messages
      .map((message) => MessageWrapper.fromJson(message))
      .toList(growable: false);
}

PermissionRequest permissionRequestFromAcp({
  required String requestId,
  required String sessionId,
  required Map<String, dynamic> request,
}) {
  final toolCall = _asObject(request['toolCall']);
  final options = (request['options'] as List<dynamic>? ?? const [])
      .map(_asObject)
      .whereType<Map<String, dynamic>>()
      .toList(growable: false);

  return PermissionRequest.fromJson({
    'id': requestId,
    'sessionID': sessionId,
    'permission':
        _asString(toolCall?['title']) ??
        _asString(toolCall?['kind']) ??
        'permission',
    'patterns': options
        .map((option) => _asString(option['name']))
        .whereType<String>()
        .toList(growable: false),
    'metadata': {
      'toolCall': toolCall,
      'options': options,
    },
    'always': options
        .map((option) => _asString(option['kind']))
        .where((kind) => kind == 'allow_always')
        .toList(growable: false),
    'tool': {
      'messageID': 'assistant:$sessionId',
      'callID': _asString(toolCall?['toolCallId']) ?? requestId,
    },
  });
}

const Set<String> _assistantEntryKinds = {
  'agent_message_chunk',
  'agent_thought_chunk',
  'tool_call',
  'tool_call_update',
  'plan',
};

class _AssistantBuilder {
  final Map<String, dynamic> message;
  final Map<String, int> partIndexByKey = <String, int>{};

  _AssistantBuilder(this.message);

  List<Map<String, dynamic>> get parts =>
      (message['parts'] as List<dynamic>).cast<Map<String, dynamic>>();
}

int _isoToMillis(String? value) {
  if (value == null || value.isEmpty) {
    return DateTime.now().millisecondsSinceEpoch;
  }
  return DateTime.tryParse(value)?.millisecondsSinceEpoch ??
      DateTime.now().millisecondsSinceEpoch;
}

Map<String, dynamic>? _asObject(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return null;
}

String? _asString(Object? value) {
  return value is String ? value : null;
}

String _extractTextContent(Object? content) {
  final object = _asObject(content);
  if (object == null) {
    return '';
  }
  if (object['type'] == 'text' && object['text'] is String) {
    return object['text'] as String;
  }
  if (object['type'] == 'resource_link') {
    final title = _asString(object['title']);
    final uri = _asString(object['uri']);
    return [title, uri].whereType<String>().join(' ').trim();
  }
  return '';
}

String _stringifyValue(Object? value) {
  if (value == null) {
    return '';
  }
  if (value is String) {
    return value;
  }
  return value.toString();
}

String _toolStatus(Object? status) {
  return switch (status) {
    'in_progress' => 'running',
    'failed' => 'error',
    'completed' => 'completed',
    'pending' => 'pending',
    _ => 'pending',
  };
}

String _toolName(Object? kind, Object? title) {
  if (title is String && title.trim().isNotEmpty) {
    return title.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');
  }
  if (kind is String && kind.trim().isNotEmpty) {
    return kind;
  }
  return 'tool';
}

Map<String, dynamic> _createUserMessage(
  Session session,
  String entryId,
  String text,
  String createdAt,
  String currentMode,
) {
  final created = _isoToMillis(createdAt);
  return {
    'info': {
      'id': entryId,
      'sessionID': session.id,
      'role': 'user',
      'agent': currentMode,
      'time': {
        'created': created,
        'completed': created,
      },
    },
    'parts': [
      {
        'id': '$entryId:text',
        'sessionID': session.id,
        'messageID': entryId,
        'type': 'text',
        'text': text,
        'synthetic': false,
        'time': {
          'start': created,
          'end': created,
        },
      },
    ],
  };
}

Map<String, dynamic> _createAssistantMessage(
  Session session,
  String messageId,
  String createdAt,
  String currentMode,
  String? parentId,
) {
  final created = _isoToMillis(createdAt);
  return {
    'info': {
      'id': messageId,
      'sessionID': session.id,
      'role': 'assistant',
      ...(parentId == null
          ? const <String, dynamic>{}
          : <String, dynamic>{'parentID': parentId}),
      'modelID': 'default',
      'providerID': 'local',
      'mode': currentMode,
      'agent': session.agentID,
      'path': {
        'cwd': session.directory,
        'root': session.directory,
      },
      'cost': 0,
      'tokens': {
        'input': 0,
        'output': 0,
        'reasoning': 0,
        'cache': {
          'read': 0,
          'write': 0,
        },
      },
      'time': {
        'created': created,
      },
    },
    'parts': <Map<String, dynamic>>[],
  };
}

void _appendOrMergeTextPart(
  _AssistantBuilder builder,
  String partType,
  String delta,
  String createdAt,
) {
  final key = partType;
  final created = _isoToMillis(createdAt);
  final index = builder.partIndexByKey[key];
  if (index == null) {
    builder.parts.add({
      'id': '${builder.message['info']['id']}:$partType',
      'sessionID': builder.message['info']['sessionID'],
      'messageID': builder.message['info']['id'],
      'type': partType,
      'text': delta,
      'time': {
        'start': created,
        'end': created,
      },
    });
    builder.partIndexByKey[key] = builder.parts.length - 1;
    return;
  }

  final current = builder.parts[index];
  current['text'] = '${_asString(current['text']) ?? ''}$delta';
  current['time'] = {
    'start': _asObject(current['time'])?['start'] ?? created,
    'end': created,
  };
}

void _upsertToolPart(
  _AssistantBuilder builder,
  String entryId,
  String toolCallId,
  Map<String, dynamic> value,
) {
  final key = 'tool:$toolCallId';
  final nextState = <String, dynamic>{
    'status': _toolStatus(value['status']),
  };
  if (value.containsKey('rawInput')) {
    nextState['input'] = value['rawInput'] is Map
        ? Map<String, dynamic>.from(value['rawInput'] as Map)
        : {'raw': _stringifyValue(value['rawInput'])};
  }
  if (value.containsKey('rawOutput')) {
    nextState['output'] = _stringifyValue(value['rawOutput']);
  }
  if (value.containsKey('title')) {
    nextState['title'] = value['title'];
  }
  if (value.containsKey('locations')) {
    nextState['metadata'] = {
      'locations': value['locations'],
    };
  }

  final currentIndex = builder.partIndexByKey[key];
  if (currentIndex == null) {
    builder.parts.add({
      'id': '$entryId:tool:$toolCallId',
      'sessionID': builder.message['info']['sessionID'],
      'messageID': builder.message['info']['id'],
      'type': 'tool',
      'callID': toolCallId,
      'tool': _toolName(value['kind'], value['title']),
      'state': nextState,
    });
    builder.partIndexByKey[key] = builder.parts.length - 1;
    return;
  }

  final current = builder.parts[currentIndex];
  final mergedState = {
    ...(_asObject(current['state']) ?? <String, dynamic>{}),
    ...nextState,
  };
  current['tool'] = _toolName(value['kind'] ?? current['tool'], value['title']);
  current['state'] = mergedState;
}

void _upsertPlanPart(_AssistantBuilder builder, Map<String, dynamic> plan) {
  final entries = (plan['entries'] as List<dynamic>? ?? const []);
  final text = entries
      .map((entry) => _asObject(entry))
      .whereType<Map<String, dynamic>>()
      .map((item) {
        final status = _asString(item['status']) ?? 'pending';
        final prefix = switch (status) {
          'completed' => '[x]',
          'in_progress' => '[>]',
          _ => '[ ]',
        };
        return '$prefix ${_asString(item['content']) ?? ''}'.trim();
      })
      .where((line) => line.isNotEmpty)
      .join('\n');

  if (text.isEmpty) {
    return;
  }

  final key = 'plan';
  final part = {
    'id': '${builder.message['info']['id']}:plan',
    'sessionID': builder.message['info']['sessionID'],
    'messageID': builder.message['info']['id'],
    'type': 'reasoning',
    'text': text,
  };
  final currentIndex = builder.partIndexByKey[key];
  if (currentIndex == null) {
    builder.parts.add(part);
    builder.partIndexByKey[key] = builder.parts.length - 1;
    return;
  }
  builder.parts[currentIndex] = part;
}
