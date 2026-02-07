class PartTime {
  final int start;
  final int? end;

  PartTime({required this.start, this.end});

  factory PartTime.fromJson(Map<String, dynamic> json) {
    return PartTime(
      start: json['start'] as int,
      end: json['end'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'start': start,
      if (end != null) 'end': end,
    };
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
      _ => UnknownPart.fromJson(json),
    };
  }

  Map<String, dynamic> toJson();
}

class TextPart extends Part {
  final String text;
  final bool? synthetic;
  final bool? ignored;
  final PartTime? time;
  final Map<String, dynamic>? metadata;

  TextPart({
    required super.id,
    required super.sessionID,
    required super.messageID,
    required this.text,
    this.synthetic,
    this.ignored,
    this.time,
    this.metadata,
  }) : super(type: 'text');

  factory TextPart.fromJson(Map<String, dynamic> json) {
    return TextPart(
      id: json['id'] as String,
      sessionID: json['sessionID'] as String,
      messageID: json['messageID'] as String,
      text: json['text'] as String,
      synthetic: json['synthetic'] as bool?,
      ignored: json['ignored'] as bool?,
      time: json['time'] != null
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
      callID: json['callID'] as String,
      tool: json['tool'] as String,
      state: Map<String, dynamic>.from(json['state'] as Map),
    );
  }

  String get status => state['status'] as String? ?? 'pending';
  String? get title =>
      (state['title'] ?? (state['metadata'] as Map?)?['title']) as String?;
  String? get input => state['input'] as String?;
  String? get output => state['output'] as String?;
  String? get error => state['error'] as String?;

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
  final String filename;
  final String url;

  FilePart({
    required super.id,
    required super.sessionID,
    required super.messageID,
    required this.mime,
    required this.filename,
    required this.url,
  }) : super(type: 'file');

  factory FilePart.fromJson(Map<String, dynamic> json) {
    return FilePart(
      id: json['id'] as String,
      sessionID: json['sessionID'] as String,
      messageID: json['messageID'] as String,
      mime: json['mime'] as String,
      filename: json['filename'] as String,
      url: json['url'] as String,
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
      'filename': filename,
      'url': url,
    };
  }
}

class ReasoningPart extends Part {
  final String text;
  final PartTime time;

  ReasoningPart({
    required super.id,
    required super.sessionID,
    required super.messageID,
    required this.text,
    required this.time,
  }) : super(type: 'reasoning');

  factory ReasoningPart.fromJson(Map<String, dynamic> json) {
    return ReasoningPart(
      id: json['id'] as String,
      sessionID: json['sessionID'] as String,
      messageID: json['messageID'] as String,
      text: json['text'] as String,
      time: PartTime.fromJson(json['time'] as Map<String, dynamic>),
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
      'time': time.toJson(),
    };
  }
}

class StepStartPart extends Part {
  StepStartPart({
    required super.id,
    required super.sessionID,
    required super.messageID,
  }) : super(type: 'step-start');

  factory StepStartPart.fromJson(Map<String, dynamic> json) {
    return StepStartPart(
      id: json['id'] as String,
      sessionID: json['sessionID'] as String,
      messageID: json['messageID'] as String,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sessionID': sessionID,
      'messageID': messageID,
      'type': type,
    };
  }
}

class StepFinishPart extends Part {
  final String? reason;
  final String? snapshot;
  final Map<String, dynamic>? cost;
  final Map<String, dynamic>? tokens;

  StepFinishPart({
    required super.id,
    required super.sessionID,
    required super.messageID,
    this.reason,
    this.snapshot,
    this.cost,
    this.tokens,
  }) : super(type: 'step-finish');

  factory StepFinishPart.fromJson(Map<String, dynamic> json) {
    return StepFinishPart(
      id: json['id'] as String,
      sessionID: json['sessionID'] as String,
      messageID: json['messageID'] as String,
      reason: json['reason'] as String?,
      snapshot: json['snapshot'] as String?,
      cost: json['cost'] as Map<String, dynamic>?,
      tokens: json['tokens'] as Map<String, dynamic>?,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sessionID': sessionID,
      'messageID': messageID,
      'type': type,
      if (reason != null) 'reason': reason,
      if (snapshot != null) 'snapshot': snapshot,
      if (cost != null) 'cost': cost,
      if (tokens != null) 'tokens': tokens,
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
      snapshot: json['snapshot'] as String,
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
  final List<dynamic> files;

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
      hash: json['hash'] as String,
      files: List<dynamic>.from(json['files'] as List),
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
  final String? source;

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
      name: json['name'] as String,
      source: json['source'] as String?,
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
  final String? error;
  final PartTime? time;

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
      attempt: json['attempt'] as int,
      error: json['error'] as String?,
      time: json['time'] != null
          ? PartTime.fromJson(json['time'] as Map<String, dynamic>)
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
      'attempt': attempt,
      if (error != null) 'error': error,
      if (time != null) 'time': time!.toJson(),
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
      auto: json['auto'] as bool,
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
      id: json['id'] as String,
      sessionID: json['sessionID'] as String,
      messageID: json['messageID'] as String,
      type: json['type'] as String,
      raw: json,
    );
  }

  @override
  Map<String, dynamic> toJson() => _raw;
}
