class Command {
  final String name;
  final String? description;
  final String? agent;
  final String? model;
  final String? source;
  final String template;
  final bool? subtask;
  final List<String> hints;

  Command({
    required this.name,
    this.description,
    this.agent,
    this.model,
    this.source,
    required this.template,
    this.subtask,
    this.hints = const [],
  });

  factory Command.fromJson(Map<String, dynamic> json) {
    return Command(
      name: json['name'] as String,
      description: json['description'] as String?,
      agent: json['agent'] as String?,
      model: json['model'] as String?,
      source: json['source'] as String?,
      template: json['template'] as String,
      subtask: json['subtask'] as bool?,
      hints: (json['hints'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      if (description != null) 'description': description,
      if (agent != null) 'agent': agent,
      if (model != null) 'model': model,
      if (source != null) 'source': source,
      'template': template,
      if (subtask != null) 'subtask': subtask,
      'hints': hints,
    };
  }
}
