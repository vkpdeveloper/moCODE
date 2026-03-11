class PtyInfo {
  final String id;
  final String title;
  final String command;
  final List<String> args;
  final String cwd;
  final String status;
  final int pid;
  final int? exitCode;

  const PtyInfo({
    required this.id,
    required this.title,
    required this.command,
    required this.args,
    required this.cwd,
    required this.status,
    required this.pid,
    this.exitCode,
  });

  factory PtyInfo.fromJson(Map<String, dynamic> json) {
    return PtyInfo(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      command: json['command'] as String? ?? '',
      args: (json['args'] as List<dynamic>?)?.cast<String>() ?? const [],
      cwd: json['cwd'] as String? ?? '',
      status: json['status'] as String? ?? 'running',
      pid: (json['pid'] as num?)?.toInt() ?? 0,
      exitCode: (json['exitCode'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'command': command,
      'args': args,
      'cwd': cwd,
      'status': status,
      'pid': pid,
      if (exitCode != null) 'exitCode': exitCode,
    };
  }

  PtyInfo copyWith({
    String? title,
    String? command,
    List<String>? args,
    String? cwd,
    String? status,
    int? pid,
    int? exitCode,
  }) {
    return PtyInfo(
      id: id,
      title: title ?? this.title,
      command: command ?? this.command,
      args: args ?? this.args,
      cwd: cwd ?? this.cwd,
      status: status ?? this.status,
      pid: pid ?? this.pid,
      exitCode: exitCode ?? this.exitCode,
    );
  }
}
