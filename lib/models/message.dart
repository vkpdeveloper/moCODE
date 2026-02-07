import 'part.dart';

class MessageTime {
  final int created;
  final int? completed;

  MessageTime({required this.created, this.completed});

  factory MessageTime.fromJson(Map<String, dynamic> json) {
    return MessageTime(
      created: json['created'] as int,
      completed: json['completed'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'created': created,
      if (completed != null) 'completed': completed,
    };
  }
}

class MessageModel {
  final String providerID;
  final String modelID;

  MessageModel({required this.providerID, required this.modelID});

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    return MessageModel(
      providerID: json['providerID'] as String,
      modelID: json['modelID'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'providerID': providerID,
      'modelID': modelID,
    };
  }
}

class MessagePath {
  final String cwd;
  final String root;

  MessagePath({required this.cwd, required this.root});

  factory MessagePath.fromJson(Map<String, dynamic> json) {
    return MessagePath(
      cwd: json['cwd'] as String,
      root: json['root'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'cwd': cwd,
      'root': root,
    };
  }
}

class MessageTokens {
  final int input;
  final int output;
  final int reasoning;
  final MessageCacheTokens cache;

  MessageTokens({
    required this.input,
    required this.output,
    required this.reasoning,
    required this.cache,
  });

  factory MessageTokens.fromJson(Map<String, dynamic> json) {
    return MessageTokens(
      input: (json['input'] as num?)?.toInt() ?? 0,
      output: (json['output'] as num?)?.toInt() ?? 0,
      reasoning: (json['reasoning'] as num?)?.toInt() ?? 0,
      cache: json['cache'] != null
          ? MessageCacheTokens.fromJson(json['cache'] as Map<String, dynamic>)
          : MessageCacheTokens(read: 0, write: 0),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'input': input,
      'output': output,
      'reasoning': reasoning,
      'cache': cache.toJson(),
    };
  }
}

class MessageCacheTokens {
  final int read;
  final int write;

  MessageCacheTokens({required this.read, required this.write});

  factory MessageCacheTokens.fromJson(Map<String, dynamic> json) {
    return MessageCacheTokens(
      read: (json['read'] as num?)?.toInt() ?? 0,
      write: (json['write'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'read': read,
      'write': write,
    };
  }
}

class MessageSummary {
  final String? title;
  final String? body;

  MessageSummary({this.title, this.body});

  factory MessageSummary.fromJson(Map<String, dynamic> json) {
    return MessageSummary(
      title: json['title'] as String?,
      body: json['body'] as String?,
    );
  }
}

class MessageError {
  final String name;
  final dynamic data;

  MessageError({required this.name, this.data});

  factory MessageError.fromJson(Map<String, dynamic> json) {
    return MessageError(
      name: json['name'] as String? ?? 'Unknown',
      data: json['data'],
    );
  }

  @override
  String toString() => name;
}

sealed class MessageInfo {
  final String id;
  final String sessionID;
  final String role;

  MessageInfo({
    required this.id,
    required this.sessionID,
    required this.role,
  });

  factory MessageInfo.fromJson(Map<String, dynamic> json) {
    final role = json['role'] as String;
    if (role == 'user') {
      return UserMessageInfo.fromJson(json);
    } else {
      return AssistantMessageInfo.fromJson(json);
    }
  }

  Map<String, dynamic> toJson();
}

class UserMessageInfo extends MessageInfo {
  final MessageTime time;
  final String? agent;
  final MessageModel? model;
  final MessageSummary? summary;
  final String? system;
  final String? variant;

  UserMessageInfo({
    required super.id,
    required super.sessionID,
    required this.time,
    this.agent,
    this.model,
    this.summary,
    this.system,
    this.variant,
  }) : super(role: 'user');

  factory UserMessageInfo.fromJson(Map<String, dynamic> json) {
    return UserMessageInfo(
      id: json['id'] as String,
      sessionID: json['sessionID'] as String,
      time: MessageTime.fromJson(json['time'] as Map<String, dynamic>),
      agent: json['agent'] as String?,
      model: json['model'] != null
          ? MessageModel.fromJson(json['model'] as Map<String, dynamic>)
          : null,
      summary: json['summary'] is Map<String, dynamic>
          ? MessageSummary.fromJson(json['summary'] as Map<String, dynamic>)
          : null,
      system: json['system'] as String?,
      variant: json['variant'] is String ? json['variant'] as String : json['variant']?.toString(),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sessionID': sessionID,
      'role': role,
      'time': time.toJson(),
      if (agent != null) 'agent': agent,
      if (model != null) 'model': model!.toJson(),
      if (system != null) 'system': system,
      if (variant != null) 'variant': variant,
    };
  }
}

class AssistantMessageInfo extends MessageInfo {
  final MessageTime time;
  final MessageError? error;
  final String? parentID;
  final String modelID;
  final String providerID;
  final String mode;
  final String? agent;
  final MessagePath? path;
  final bool? isSummary;
  final double cost;
  final MessageTokens tokens;
  final String? finish;

  AssistantMessageInfo({
    required super.id,
    required super.sessionID,
    required this.time,
    this.error,
    this.parentID,
    required this.modelID,
    required this.providerID,
    required this.mode,
    this.agent,
    this.path,
    this.isSummary,
    required this.cost,
    required this.tokens,
    this.finish,
  }) : super(role: 'assistant');

  factory AssistantMessageInfo.fromJson(Map<String, dynamic> json) {
    return AssistantMessageInfo(
      id: json['id'] as String,
      sessionID: json['sessionID'] as String,
      time: MessageTime.fromJson(json['time'] as Map<String, dynamic>),
      error: json['error'] is Map<String, dynamic>
          ? MessageError.fromJson(json['error'] as Map<String, dynamic>)
          : null,
      parentID: json['parentID'] as String?,
      modelID: json['modelID'] as String? ?? '',
      providerID: json['providerID'] as String? ?? '',
      mode: json['mode'] as String? ?? '',
      agent: json['agent'] as String?,
      path: json['path'] is Map<String, dynamic>
          ? MessagePath.fromJson(json['path'] as Map<String, dynamic>)
          : null,
      isSummary: json['summary'] as bool?,
      cost: (json['cost'] as num?)?.toDouble() ?? 0.0,
      tokens: json['tokens'] is Map<String, dynamic>
          ? MessageTokens.fromJson(json['tokens'] as Map<String, dynamic>)
          : MessageTokens(
              input: 0,
              output: 0,
              reasoning: 0,
              cache: MessageCacheTokens(read: 0, write: 0),
            ),
      finish: json['finish'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sessionID': sessionID,
      'role': role,
      'time': time.toJson(),
      if (parentID != null) 'parentID': parentID,
      'modelID': modelID,
      'providerID': providerID,
      'mode': mode,
      if (agent != null) 'agent': agent,
      if (path != null) 'path': path!.toJson(),
      'cost': cost,
      'tokens': tokens.toJson(),
      if (finish != null) 'finish': finish,
    };
  }
}

class MessageWrapper {
  final MessageInfo info;
  final List<Part> parts;

  MessageWrapper({required this.info, required this.parts});

  factory MessageWrapper.fromJson(Map<String, dynamic> json) {
    return MessageWrapper(
      info: MessageInfo.fromJson(json['info'] as Map<String, dynamic>),
      parts: (json['parts'] as List<dynamic>)
          .map((e) => Part.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'info': info.toJson(),
      'parts': parts.map((e) => e.toJson()).toList(),
    };
  }
}
