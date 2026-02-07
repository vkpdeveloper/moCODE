class AgentModel {
  final String modelID;
  final String providerID;

  AgentModel({
    required this.modelID,
    required this.providerID,
  });

  factory AgentModel.fromJson(Map<String, dynamic> json) {
    return AgentModel(
      modelID: json['modelID'] as String,
      providerID: json['providerID'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'modelID': modelID,
      'providerID': providerID,
    };
  }
}

class Agent {
  final String name;
  final String? description;
  final String mode;
  final bool? native;
  final bool? hidden;
  final double? topP;
  final double? temperature;
  final String? color;
  final AgentModel? model;
  final String? prompt;
  final int? steps;

  Agent({
    required this.name,
    this.description,
    required this.mode,
    this.native,
    this.hidden,
    this.topP,
    this.temperature,
    this.color,
    this.model,
    this.prompt,
    this.steps,
  });

  factory Agent.fromJson(Map<String, dynamic> json) {
    return Agent(
      name: json['name'] as String,
      description: json['description'] as String?,
      mode: json['mode'] as String,
      native: json['native'] as bool?,
      hidden: json['hidden'] as bool?,
      topP: (json['topP'] as num?)?.toDouble(),
      temperature: (json['temperature'] as num?)?.toDouble(),
      color: json['color'] as String?,
      model: json['model'] != null
          ? AgentModel.fromJson(json['model'] as Map<String, dynamic>)
          : null,
      prompt: json['prompt'] as String?,
      steps: json['steps'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      if (description != null) 'description': description,
      'mode': mode,
      if (native != null) 'native': native,
      if (hidden != null) 'hidden': hidden,
      if (topP != null) 'topP': topP,
      if (temperature != null) 'temperature': temperature,
      if (color != null) 'color': color,
      if (model != null) 'model': model!.toJson(),
      if (prompt != null) 'prompt': prompt,
      if (steps != null) 'steps': steps,
    };
  }
}
