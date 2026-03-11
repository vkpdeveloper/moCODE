class ModelCost {
  final double input;
  final double output;
  final double? cacheRead;
  final double? cacheWrite;

  ModelCost({
    required this.input,
    required this.output,
    this.cacheRead,
    this.cacheWrite,
  });

  factory ModelCost.fromJson(Map<String, dynamic> json) {
    return ModelCost(
      input: (json['input'] as num).toDouble(),
      output: (json['output'] as num).toDouble(),
      cacheRead: (json['cache_read'] as num?)?.toDouble(),
      cacheWrite: (json['cache_write'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'input': input,
      'output': output,
      if (cacheRead != null) 'cache_read': cacheRead,
      if (cacheWrite != null) 'cache_write': cacheWrite,
    };
  }
}

class ModelLimit {
  final int context;
  final int? input;
  final int? output;

  ModelLimit({
    required this.context,
    this.input,
    this.output,
  });

  factory ModelLimit.fromJson(Map<String, dynamic> json) {
    return ModelLimit(
      context: json['context'] as int,
      input: json['input'] as int?,
      output: json['output'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'context': context,
      if (input != null) 'input': input,
      if (output != null) 'output': output,
    };
  }
}

class ModelInfo {
  final String id;
  final String name;
  final String? family;
  final String releaseDate;
  final bool attachment;
  final bool reasoning;
  final bool temperature;
  final bool toolCall;
  final ModelCost? cost;
  final ModelLimit limit;

  ModelInfo({
    required this.id,
    required this.name,
    this.family,
    required this.releaseDate,
    required this.attachment,
    required this.reasoning,
    required this.temperature,
    required this.toolCall,
    this.cost,
    required this.limit,
  });

  factory ModelInfo.fromJson(Map<String, dynamic> json) {
    return ModelInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      family: json['family'] as String?,
      releaseDate: json['release_date'] as String,
      attachment: json['attachment'] as bool,
      reasoning: json['reasoning'] as bool,
      temperature: json['temperature'] as bool,
      toolCall: json['tool_call'] as bool,
      cost: json['cost'] != null
          ? ModelCost.fromJson(json['cost'] as Map<String, dynamic>)
          : null,
      limit: ModelLimit.fromJson(json['limit'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      if (family != null) 'family': family,
      'release_date': releaseDate,
      'attachment': attachment,
      'reasoning': reasoning,
      'temperature': temperature,
      'tool_call': toolCall,
      if (cost != null) 'cost': cost!.toJson(),
      'limit': limit.toJson(),
    };
  }
}

class ProviderInfo {
  final String id;
  final String name;
  final List<String> env;
  final String? npm;
  final Map<String, ModelInfo> models;

  ProviderInfo({
    required this.id,
    required this.name,
    required this.env,
    this.npm,
    required this.models,
  });

  factory ProviderInfo.fromJson(Map<String, dynamic> json) {
    return ProviderInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      env: (json['env'] as List<dynamic>).map((e) => e as String).toList(),
      npm: json['npm'] as String?,
      models: (json['models'] as Map<String, dynamic>).map(
        (key, value) =>
            MapEntry(key, ModelInfo.fromJson(value as Map<String, dynamic>)),
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'env': env,
      if (npm != null) 'npm': npm,
      'models': models.map((key, value) => MapEntry(key, value.toJson())),
    };
  }
}

class ProviderListResponse {
  final List<ProviderInfo> all;
  final Map<String, String> default_;
  final List<String> connected;

  ProviderListResponse({
    required this.all,
    required this.default_,
    required this.connected,
  });

  factory ProviderListResponse.fromJson(Map<String, dynamic> json) {
    return ProviderListResponse(
      all: (json['all'] as List<dynamic>)
          .map((e) => ProviderInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
      default_: Map<String, String>.from(json['default'] as Map),
      connected:
          (json['connected'] as List<dynamic>).map((e) => e as String).toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'all': all.map((e) => e.toJson()).toList(),
      'default': default_,
      'connected': connected,
    };
  }
}
