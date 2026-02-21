class PartTime {
  final int start;
  final int? end;

  PartTime({required this.start, this.end});

  factory PartTime.fromJson(Map<String, dynamic> json) {
    return PartTime(
      start: (json['start'] as num).toInt(),
      end: (json['end'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() {
    return {'start': start, if (end != null) 'end': end};
  }
}

sealed class Part {
  final String id;
  final String sessionID;
  final String messageID;
  final String type;

  Part({
    required this.id,
    required this.sessionID,
    required this.messageID,
    required this.type,
  });

  factory Part.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    return switch (type) {
      'text' => TextPart.fromJson(json),
      'tool' => ToolPart.fromJson(json),
      'file' => FilePart.fromJson(json),
      'reasoning' => ReasoningPart.fromJson(json),
      'step-start' => StepStartPart.fromJson(json),
      'step-finish' => StepFinishPart.fromJson(json),
      'snapshot' => SnapshotPart.fromJson(json),
      'patch' => PatchPart.fromJson(json),
      'agent' => AgentPart.fromJson(json),
      'retry' => RetryPart.fromJson(json),
      'compaction' => CompactionPart.fromJson(json),
      'subtask' => SubtaskPart.fromJson(json),
      'command-output' => CommandOutputPart.fromJson(json),
      _ => UnknownPart.fromJson(json),
    };
  }

  Map<String, dynamic> toJson();
}

class TextPart extends Part {
  final String text;
  final bool? ignored;
  final bool synthetic;
  final PartTime? time;
  final Map<String, dynamic>? metadata;

  TextPart({
    required super.id,
    required super.sessionID,
    required super.messageID,
    required this.synthetic,
    required this.text,
    this.ignored,
    this.time,
    this.metadata,
  }) : super(type: 'text');

  factory TextPart.fromJson(Map<String, dynamic> json) {
    return TextPart(
      id: json['id'] as String,
      sessionID: json['sessionID'] as String,
      messageID: json['messageID'] as String,
      text: json['text'] as String? ?? '',
      ignored: json['ignored'] as bool?,
      time: json['time'] is Map<String, dynamic>
          ? PartTime.fromJson(json['time'] as Map<String, dynamic>)
          : null,
      metadata: json['metadata'] as Map<String, dynamic>?,
      synthetic: json['synthetic'] != null ? json['synthetic'] as bool : false,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sessionID': sessionID,
      'messageID': messageID,
      'type': type,
      'text': text,
      if (synthetic != null) 'synthetic': synthetic,
      if (ignored != null) 'ignored': ignored,
      if (time != null) 'time': time!.toJson(),
      if (metadata != null) 'metadata': metadata,
    };
  }
}

class ToolPart extends Part {
  final String callID;
  final String tool;
  final Map<String, dynamic> state;

  ToolPart({
    required super.id,
    required super.sessionID,
    required super.messageID,
    required this.callID,
    required this.tool,
    required this.state,
  }) : super(type: 'tool');

  factory ToolPart.fromJson(Map<String, dynamic> json) {
    return ToolPart(
      id: json['id'] as String,
      sessionID: json['sessionID'] as String,
      messageID: json['messageID'] as String,
      callID: json['callID'] as String? ?? '',
      tool: json['tool'] as String? ?? '',
      state: json['state'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(json['state'] as Map)
          : <String, dynamic>{},
    );
  }

  String get status => state['status'] as String? ?? 'pending';

  String? get title {
    final t = state['title'];
    if (t is String) return t;
    final meta = state['metadata'];
    if (meta is Map<String, dynamic>) {
      final mt = meta['title'];
      if (mt is String) return mt;
    }
    return null;
  }

  String? get input {
    final i = state['input'];
    if (i is String) return i;
    if (i is Map) return i.toString();
    return null;
  }

  String? get output {
    final o = state['output'];
    if (o is String) return o;
    return o?.toString();
  }

  String? get error {
    final e = state['error'];
    if (e is String) return e;
    if (e is Map) return e['message']?.toString() ?? e.toString();
    return null;
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sessionID': sessionID,
      'messageID': messageID,
      'type': type,
      'callID': callID,
      'tool': tool,
      'state': state,
    };
  }
}

class FilePart extends Part {
  final String mime;
  final String? filename;
  final String url;
  final Map<String, dynamic>? source;

  FilePart({
    required super.id,
    required super.sessionID,
    required super.messageID,
    required this.mime,
    this.filename,
    required this.url,
    this.source,
  }) : super(type: 'file');

  factory FilePart.fromJson(Map<String, dynamic> json) {
    return FilePart(
      id: json['id'] as String,
      sessionID: json['sessionID'] as String,
      messageID: json['messageID'] as String,
      mime: json['mime'] as String? ?? '',
      filename: json['filename'] as String?,
      url: json['url'] as String? ?? '',
      source: json['source'] is Map<String, dynamic>
          ? json['source'] as Map<String, dynamic>
          : null,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sessionID': sessionID,
      'messageID': messageID,
      'type': type,
      'mime': mime,
      if (filename != null) 'filename': filename,
      'url': url,
      if (source != null) 'source': source,
    };
  }
}

class ReasoningPart extends Part {
  final String text;
  final PartTime? time;
  final Map<String, dynamic>? metadata;

  ReasoningPart({
    required super.id,
    required super.sessionID,
    required super.messageID,
    required this.text,
    this.time,
    this.metadata,
  }) : super(type: 'reasoning');

  factory ReasoningPart.fromJson(Map<String, dynamic> json) {
    return ReasoningPart(
      id: json['id'] as String,
      sessionID: json['sessionID'] as String,
      messageID: json['messageID'] as String,
      text: json['text'] as String? ?? '',
      time: json['time'] is Map<String, dynamic>
          ? PartTime.fromJson(json['time'] as Map<String, dynamic>)
          : null,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sessionID': sessionID,
      'messageID': messageID,
      'type': type,
      'text': text,
      if (time != null) 'time': time!.toJson(),
      if (metadata != null) 'metadata': metadata,
    };
  }
}

class StepStartPart extends Part {
  final String? snapshot;

  StepStartPart({
    required super.id,
    required super.sessionID,
    required super.messageID,
    this.snapshot,
  }) : super(type: 'step-start');

  factory StepStartPart.fromJson(Map<String, dynamic> json) {
    return StepStartPart(
      id: json['id'] as String,
      sessionID: json['sessionID'] as String,
      messageID: json['messageID'] as String,
      snapshot: json['snapshot'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sessionID': sessionID,
      'messageID': messageID,
      'type': type,
      if (snapshot != null) 'snapshot': snapshot,
    };
  }
}

class StepFinishPart extends Part {
  final String reason;
  final String? snapshot;
  final double cost;
  final int inputTokens;
  final int outputTokens;

  StepFinishPart({
    required super.id,
    required super.sessionID,
    required super.messageID,
    required this.reason,
    this.snapshot,
    required this.cost,
    required this.inputTokens,
    required this.outputTokens,
  }) : super(type: 'step-finish');

  factory StepFinishPart.fromJson(Map<String, dynamic> json) {
    final tokens = json['tokens'];
    int inTok = 0;
    int outTok = 0;
    if (tokens is Map<String, dynamic>) {
      inTok = (tokens['input'] as num?)?.toInt() ?? 0;
      outTok = (tokens['output'] as num?)?.toInt() ?? 0;
    }

    return StepFinishPart(
      id: json['id'] as String,
      sessionID: json['sessionID'] as String,
      messageID: json['messageID'] as String,
      reason: json['reason'] as String? ?? '',
      snapshot: json['snapshot'] as String?,
      cost: (json['cost'] as num?)?.toDouble() ?? 0.0,
      inputTokens: inTok,
      outputTokens: outTok,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sessionID': sessionID,
      'messageID': messageID,
      'type': type,
      'reason': reason,
      if (snapshot != null) 'snapshot': snapshot,
      'cost': cost,
    };
  }
}

class SnapshotPart extends Part {
  final String snapshot;

  SnapshotPart({
    required super.id,
    required super.sessionID,
    required super.messageID,
    required this.snapshot,
  }) : super(type: 'snapshot');

  factory SnapshotPart.fromJson(Map<String, dynamic> json) {
    return SnapshotPart(
      id: json['id'] as String,
      sessionID: json['sessionID'] as String,
      messageID: json['messageID'] as String,
      snapshot: json['snapshot'] as String? ?? '',
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sessionID': sessionID,
      'messageID': messageID,
      'type': type,
      'snapshot': snapshot,
    };
  }
}

class PatchPart extends Part {
  final String hash;
  final List<String> files;

  PatchPart({
    required super.id,
    required super.sessionID,
    required super.messageID,
    required this.hash,
    required this.files,
  }) : super(type: 'patch');

  factory PatchPart.fromJson(Map<String, dynamic> json) {
    return PatchPart(
      id: json['id'] as String,
      sessionID: json['sessionID'] as String,
      messageID: json['messageID'] as String,
      hash: json['hash'] as String? ?? '',
      files: (json['files'] as List?)?.map((e) => e.toString()).toList() ?? [],
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sessionID': sessionID,
      'messageID': messageID,
      'type': type,
      'hash': hash,
      'files': files,
    };
  }
}

class AgentPart extends Part {
  final String name;
  final Map<String, dynamic>? source;

  AgentPart({
    required super.id,
    required super.sessionID,
    required super.messageID,
    required this.name,
    this.source,
  }) : super(type: 'agent');

  factory AgentPart.fromJson(Map<String, dynamic> json) {
    return AgentPart(
      id: json['id'] as String,
      sessionID: json['sessionID'] as String,
      messageID: json['messageID'] as String,
      name: json['name'] as String? ?? '',
      source: json['source'] is Map<String, dynamic>
          ? json['source'] as Map<String, dynamic>
          : null,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sessionID': sessionID,
      'messageID': messageID,
      'type': type,
      'name': name,
      if (source != null) 'source': source,
    };
  }
}

class RetryPart extends Part {
  final int attempt;
  final Map<String, dynamic>? error;
  final Map<String, dynamic>? time;

  RetryPart({
    required super.id,
    required super.sessionID,
    required super.messageID,
    required this.attempt,
    this.error,
    this.time,
  }) : super(type: 'retry');

  factory RetryPart.fromJson(Map<String, dynamic> json) {
    return RetryPart(
      id: json['id'] as String,
      sessionID: json['sessionID'] as String,
      messageID: json['messageID'] as String,
      attempt: (json['attempt'] as num?)?.toInt() ?? 0,
      error: json['error'] is Map<String, dynamic>
          ? json['error'] as Map<String, dynamic>
          : null,
      time: json['time'] is Map<String, dynamic>
          ? json['time'] as Map<String, dynamic>
          : null,
    );
  }

  String? get errorMessage {
    if (error == null) return null;
    final data = error!['data'];
    if (data is Map<String, dynamic>) {
      return data['message'] as String?;
    }
    return error!['name']?.toString();
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sessionID': sessionID,
      'messageID': messageID,
      'type': type,
      'attempt': attempt,
      if (error != null) 'error': error,
      if (time != null) 'time': time,
    };
  }
}

class SubtaskPart extends Part {
  final String prompt;
  final String description;
  final String agent;
  final Map<String, dynamic>? model;
  final String? command;

  SubtaskPart({
    required super.id,
    required super.sessionID,
    required super.messageID,
    required this.prompt,
    required this.description,
    required this.agent,
    this.model,
    this.command,
  }) : super(type: 'subtask');

  factory SubtaskPart.fromJson(Map<String, dynamic> json) {
    return SubtaskPart(
      id: json['id'] as String,
      sessionID: json['sessionID'] as String,
      messageID: json['messageID'] as String,
      prompt: json['prompt'] as String? ?? '',
      description: json['description'] as String? ?? '',
      agent: json['agent'] as String? ?? '',
      model: json['model'] is Map<String, dynamic>
          ? json['model'] as Map<String, dynamic>
          : null,
      command: json['command'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sessionID': sessionID,
      'messageID': messageID,
      'type': type,
      'prompt': prompt,
      'description': description,
      'agent': agent,
      if (model != null) 'model': model,
      if (command != null) 'command': command,
    };
  }
}

class CommandOutputPart extends Part {
  final String command;
  final List<String> args;
  final String cwd;
  final String? status;
  final int? exitCode;
  final PartTime? time;
  final Map<String, dynamic>? metadata;

  CommandOutputPart({
    required super.id,
    required super.sessionID,
    required super.messageID,
    required this.command,
    this.args = const [],
    required this.cwd,
    this.status,
    this.exitCode,
    this.time,
    this.metadata,
  }) : super(type: 'command-output');

  factory CommandOutputPart.fromJson(Map<String, dynamic> json) {
    return CommandOutputPart(
      id: json['id'] as String,
      sessionID: json['sessionID'] as String,
      messageID: json['messageID'] as String,
      command: json['command'] as String? ?? '',
      args: (json['args'] as List<dynamic>?)?.cast<String>() ?? const [],
      cwd: json['cwd'] as String? ?? '',
      status: json['status'] as String?,
      exitCode: (json['exitCode'] as num?)?.toInt(),
      time: json['time'] is Map<String, dynamic>
          ? PartTime.fromJson(json['time'] as Map<String, dynamic>)
          : null,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sessionID': sessionID,
      'messageID': messageID,
      'type': type,
      'command': command,
      'args': args,
      'cwd': cwd,
      if (status != null) 'status': status,
      if (exitCode != null) 'exitCode': exitCode,
      if (time != null) 'time': time!.toJson(),
      if (metadata != null) 'metadata': metadata,
    };
  }
}

class CompactionPart extends Part {
  final bool auto;

  CompactionPart({
    required super.id,
    required super.sessionID,
    required super.messageID,
    required this.auto,
  }) : super(type: 'compaction');

  factory CompactionPart.fromJson(Map<String, dynamic> json) {
    return CompactionPart(
      id: json['id'] as String,
      sessionID: json['sessionID'] as String,
      messageID: json['messageID'] as String,
      auto: json['auto'] as bool? ?? false,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sessionID': sessionID,
      'messageID': messageID,
      'type': type,
      'auto': auto,
    };
  }
}

class UnknownPart extends Part {
  final Map<String, dynamic> _raw;

  UnknownPart({
    required super.id,
    required super.sessionID,
    required super.messageID,
    required super.type,
    required Map<String, dynamic> raw,
  }) : _raw = raw;

  factory UnknownPart.fromJson(Map<String, dynamic> json) {
    return UnknownPart(
      id: json['id'] as String? ?? '',
      sessionID: json['sessionID'] as String? ?? '',
      messageID: json['messageID'] as String? ?? '',
      type: json['type'] as String? ?? 'unknown',
      raw: json,
    );
  }

  @override
  Map<String, dynamic> toJson() => _raw;
}
