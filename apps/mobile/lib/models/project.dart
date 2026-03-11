class ProjectIcon {
  final String? url;
  final String? override;
  final String? color;

  ProjectIcon({this.url, this.override, this.color});

  factory ProjectIcon.fromJson(Map<String, dynamic> json) {
    return ProjectIcon(
      url: json['url'] as String?,
      override: json['override'] as String?,
      color: json['color'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (url != null) 'url': url,
      if (override != null) 'override': override,
      if (color != null) 'color': color,
    };
  }
}

class ProjectCommands {
  final String? start;

  ProjectCommands({this.start});

  factory ProjectCommands.fromJson(Map<String, dynamic> json) {
    return ProjectCommands(start: json['start'] as String?);
  }

  Map<String, dynamic> toJson() {
    return {
      if (start != null) 'start': start,
    };
  }
}

class ProjectTime {
  final int created;
  final int? updated;
  final int? initialized;

  ProjectTime({
    required this.created,
    this.updated,
    this.initialized,
  });

  factory ProjectTime.fromJson(Map<String, dynamic> json) {
    return ProjectTime(
      created: json['created'] as int,
      updated: json['updated'] as int?,
      initialized: json['initialized'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'created': created,
      if (updated != null) 'updated': updated,
      if (initialized != null) 'initialized': initialized,
    };
  }
}

class Project {
  final String id;
  final String worktree;
  final String? vcs;
  final String? name;
  final ProjectIcon? icon;
  final ProjectCommands? commands;
  final ProjectTime time;
  final List<String> sandboxes;

  Project({
    required this.id,
    required this.worktree,
    this.vcs,
    this.name,
    this.icon,
    this.commands,
    required this.time,
    this.sandboxes = const [],
  });

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'] as String,
      worktree: json['worktree'] as String,
      vcs: json['vcs'] as String?,
      name: json['name'] as String?,
      icon: json['icon'] != null
          ? ProjectIcon.fromJson(json['icon'] as Map<String, dynamic>)
          : null,
      commands: json['commands'] != null
          ? ProjectCommands.fromJson(json['commands'] as Map<String, dynamic>)
          : null,
      time: ProjectTime.fromJson(json['time'] as Map<String, dynamic>),
      sandboxes: (json['sandboxes'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'worktree': worktree,
      if (vcs != null) 'vcs': vcs,
      if (name != null) 'name': name,
      if (icon != null) 'icon': icon!.toJson(),
      if (commands != null) 'commands': commands!.toJson(),
      'time': time.toJson(),
      'sandboxes': sandboxes,
    };
  }
}
