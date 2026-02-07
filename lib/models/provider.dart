class ProviderModel {
  final String id;
  final String? name;
  final List<ProviderModelInfo> models;

  const ProviderModel({
    required this.id,
    this.name,
    this.models = const [],
  });

  factory ProviderModel.fromJson(Map<String, dynamic> json) {
    final modelsRaw = json['models'];
    final List<ProviderModelInfo> modelsList;

    if (modelsRaw is Map<String, dynamic>) {
      modelsList = modelsRaw.entries.map((e) {
        final value = e.value as Map<String, dynamic>;
        return ProviderModelInfo.fromJson(value);
      }).toList();
    } else if (modelsRaw is List) {
      modelsList = modelsRaw
          .map((m) => ProviderModelInfo.fromJson(m as Map<String, dynamic>))
          .toList();
    } else {
      modelsList = [];
    }

    return ProviderModel(
      id: json['id'] as String,
      name: json['name'] as String?,
      models: modelsList,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      if (name != null) 'name': name,
      'models': models.map((m) => m.toJson()).toList(),
    };
  }
}

class ProviderModelInfo {
  final String id;
  final String? name;
  final String? family;
  final String? status;
  final bool? reasoning;

  const ProviderModelInfo({
    required this.id,
    this.name,
    this.family,
    this.status,
    this.reasoning,
  });

  factory ProviderModelInfo.fromJson(Map<String, dynamic> json) {
    return ProviderModelInfo(
      id: json['id'] as String,
      name: json['name'] as String?,
      family: json['family'] as String?,
      status: json['status'] as String?,
      reasoning: json['reasoning'] as bool?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      if (name != null) 'name': name,
      if (family != null) 'family': family,
      if (status != null) 'status': status,
      if (reasoning != null) 'reasoning': reasoning,
    };
  }
}

class ProviderListResponse {
  final List<ProviderModel> providers;
  final Map<String, String> defaults;
  final List<String> connected;

  const ProviderListResponse({
    required this.providers,
    this.defaults = const {},
    this.connected = const [],
  });

  factory ProviderListResponse.fromJson(Map<String, dynamic> json) {
    return ProviderListResponse(
      providers: (json['all'] as List? ?? [])
          .map((p) => ProviderModel.fromJson(p as Map<String, dynamic>))
          .toList(),
      defaults: (json['default'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v.toString())) ??
          {},
      connected: (json['connected'] as List?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );
  }
}
