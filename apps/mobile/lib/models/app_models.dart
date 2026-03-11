class HealthInfo {
  final bool healthy;
  final String? version;
  final Map<String, dynamic>? raw;

  const HealthInfo({this.healthy = false, this.version, this.raw});

  factory HealthInfo.fromJson(Map<String, dynamic> json) {
    return HealthInfo(
      healthy: json['healthy'] as bool? ?? false,
      version: json['version'] as String?,
      raw: json,
    );
  }
}

class VcsInfo {
  final String? branch;
  final String? commit;
  final bool? dirty;
  final Map<String, dynamic>? raw;

  const VcsInfo({this.branch, this.commit, this.dirty, this.raw});

  factory VcsInfo.fromJson(Map<String, dynamic> json) {
    return VcsInfo(
      branch: json['branch'] as String?,
      commit: json['commit'] as String?,
      dirty: json['dirty'] as bool?,
      raw: json,
    );
  }
}

class Command {
  final String name;
  final String? description;
  final String? source;
  final List<String> hints;

  const Command({
    required this.name,
    this.description,
    this.source,
    this.hints = const [],
  });

  factory Command.fromJson(Map<String, dynamic> json) {
    return Command(
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      source: json['source'] as String?,
      hints: (json['hints'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );
  }
}

class Agent {
  final String name;
  final String? description;
  final String? mode;

  const Agent({required this.name, this.description, this.mode});

  factory Agent.fromJson(Map<String, dynamic> json) {
    return Agent(
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      mode: json['mode'] as String?,
    );
  }
}

class AppConfig {
  final Map<String, dynamic> raw;

  const AppConfig({required this.raw});

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    return AppConfig(raw: json);
  }

  dynamic operator [](String key) => raw[key];

  Map<String, dynamic> toJson() => raw;
}
